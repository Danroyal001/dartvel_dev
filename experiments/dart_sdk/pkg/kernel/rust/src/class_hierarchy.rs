// Port of lib/class_hierarchy.dart (`ClosedWorldClassHierarchy`), as far as
// the type-flow summary collector needs it: generic supertypes and
// `getClassAsInstanceOf`, closed-world subtyping between classes, subtypes
// of a class, dispatch targets and interface member names.
//
// Upstream builds every class's information eagerly, in topological order;
// here a class's information is built on first use from its supertypes',
// which gives the same result because each class's information depends on
// its supertypes' only.
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

use crate::ast::*;
use crate::core_types::{CoreTypes, Nullability};
use crate::reference_index::NodeIndex;
use crate::type_algebra::Substitution;

pub struct ClassInfo {
    /// Every class this class is a subtype of, itself included.
    pub supertypes: HashSet<CnId>,
    /// `genericSuperType`: each generic supertype's canonical
    /// instantiation, in insertion order.
    pub genericSuperType: Vec<(CnId, Supertype)>,
}

pub struct ClassHierarchy<'a> {
    pub index: &'a NodeIndex<'a>,
    pub coreTypes: &'a CoreTypes<'a>,
    infos: RefCell<HashMap<CnId, Rc<ClassInfo>>>,
    subtypes: RefCell<HashMap<CnId, Rc<Vec<CnId>>>>,
}

fn supertypesOfClass(class: &Class) -> impl Iterator<Item = &Supertype> {
    class.supertype.iter().chain(class.mixedInType.iter()).chain(class.implementedTypes.iter())
}

impl<'a> ClassHierarchy<'a> {
    pub fn new(index: &'a NodeIndex<'a>, coreTypes: &'a CoreTypes<'a>) -> Self {
        ClassHierarchy { index, coreTypes, infos: RefCell::new(HashMap::new()), subtypes: RefCell::new(HashMap::new()) }
    }

    pub fn infoFor(&self, class: CnId) -> Rc<ClassInfo> {
        if let Some(info) = self.infos.borrow().get(&class) {
            return info.clone();
        }
        let node = self.index.class(class).expect("class in the component");
        let mut supertypes = HashSet::new();
        supertypes.insert(class);
        let mut generic: Vec<(CnId, Supertype)> = Vec::new();
        for supertype in supertypesOfClass(node) {
            let superInfo = self.infoFor(supertype.className);
            supertypes.extend(superInfo.supertypes.iter().copied());
            // _recordSuperTypes.
            let superclass = self.index.class(supertype.className).unwrap();
            if supertype.typeArguments.is_empty() {
                for (key, ty) in &superInfo.genericSuperType {
                    record(&mut generic, *key, ty.clone());
                }
            } else {
                let substitution = Substitution::fromPairs(&superclass.typeParameters, &supertype.typeArguments);
                for (key, ty) in &superInfo.genericSuperType {
                    record(&mut generic, *key, substitution.substituteSupertype(ty, self.index));
                }
                record(&mut generic, supertype.className, supertype.clone());
            }
        }
        let info = Rc::new(ClassInfo { supertypes, genericSuperType: generic });
        self.infos.borrow_mut().insert(class, info.clone());
        info
    }

    /// `isSubtypeOf` between classes (closed world).
    pub fn isSubtypeOf(&self, sub: CnId, sup: CnId) -> bool {
        sub == sup || self.infoFor(sub).supertypes.contains(&sup)
    }

    /// `genericSupertypesOf`.
    pub fn genericSupertypesOf(&self, class: CnId) -> Vec<Supertype> {
        self.infoFor(class).genericSuperType.iter().map(|(_, s)| s.clone()).collect()
    }

    /// `getClassAsInstanceOf`.
    pub fn getClassAsInstanceOf(&self, class: CnId, superclass: CnId) -> Option<Supertype> {
        let superNode = self.index.class(superclass)?;
        if class == superclass {
            return Some(Supertype {
                nullability: Nullability::nonNullable,
                className: class,
                typeArguments: superNode
                    .typeParameters
                    .iter()
                    .map(|p| DartType::TypeParameter {
                        declaredNullability: computeNullabilityFromBound(p, self.index),
                        parameter: p.id,
                    })
                    .collect(),
            });
        }
        if !self.isSubtypeOf(class, superclass) {
            return None;
        }
        if superNode.typeParameters.is_empty() {
            return Some(Supertype { nullability: Nullability::nonNullable, className: superclass, typeArguments: vec![] });
        }
        self.infoFor(class).genericSuperType.iter().find(|(k, _)| *k == superclass).map(|(_, s)| s.clone())
    }

    /// `getTypeArgumentsAsInstanceOf` for an interface type.
    pub fn getInterfaceTypeArgumentsAsInstanceOfClass(
        &self,
        classReference: CnId,
        typeArguments: &[DartType],
        superclass: CnId,
    ) -> Option<Vec<DartType>> {
        if classReference == superclass {
            return Some(typeArguments.to_vec());
        }
        let casted = self.getClassAsInstanceOf(classReference, superclass)?;
        if casted.typeArguments.is_empty() {
            return Some(vec![]);
        }
        let class = self.index.class(classReference)?;
        let substitution = Substitution::fromPairs(&class.typeParameters, typeArguments);
        Some(substitution.substituteSupertype(&casted, self.index).typeArguments)
    }

    /// `computeSubtypesInformation().getSubtypesOf`: the class and every
    /// class that is a subtype of it.
    pub fn getSubtypesOf(&self, class: CnId) -> Rc<Vec<CnId>> {
        if let Some(s) = self.subtypes.borrow().get(&class) {
            return s.clone();
        }
        let mut result = Vec::new();
        for library in &self.index.component.libraries {
            for c in &library.classes {
                if self.isSubtypeOf(c.reference, class) {
                    result.push(c.reference);
                }
            }
        }
        let result = Rc::new(result);
        self.subtypes.borrow_mut().insert(class, result.clone());
        result
    }

    fn declaredMembers(&self, class: &'a Class, setters: bool, includeAbstract: bool) -> Vec<(Name, CnId)> {
        let mut out = Vec::new();
        for f in &class.fields {
            if f.flags & FIELD_STATIC != 0 {
                continue;
            }
            if setters {
                if f.setterReference.is_some() {
                    out.push((f.name, f.fieldReference));
                }
            } else {
                out.push((f.name, f.fieldReference));
            }
        }
        for p in &class.procedures {
            if p.flags & PROCEDURE_STATIC != 0 || p.kind == ProcedureKind::Factory {
                continue;
            }
            if !includeAbstract && p.flags & PROCEDURE_ABSTRACT != 0 {
                continue;
            }
            let isSetter = p.kind == ProcedureKind::Setter;
            if isSetter == setters {
                out.push((p.name, p.reference));
            }
        }
        out
    }

    /// `getDispatchTarget`: the concrete member a call to [name] on an
    /// instance of [class] runs.
    pub fn getDispatchTarget(&self, class: CnId, name: Name, setter: bool) -> Option<CnId> {
        let mut current = Some(class);
        while let Some(c) = current {
            let node = self.index.class(c)?;
            for (n, m) in self.declaredMembers(node, setter, false) {
                if n == name {
                    return Some(m);
                }
            }
            if let Some(mixin) = &node.mixedInType {
                if let Some(mixinNode) = self.index.class(mixin.className) {
                    for (n, m) in self.declaredMembers(mixinNode, setter, false) {
                        if n == name {
                            return Some(m);
                        }
                    }
                }
            }
            current = node.supertype.as_ref().map(|s| s.className);
        }
        None
    }

    /// The names of `getInterfaceMembers`: every instance member of the
    /// class's interface, declared or inherited.
    pub fn getInterfaceMemberNames(&self, class: CnId, setters: bool) -> Vec<Name> {
        let mut names = Vec::new();
        let mut seen = HashSet::new();
        let mut stack = vec![class];
        let mut visited = HashSet::new();
        while let Some(c) = stack.pop() {
            if !visited.insert(c) {
                continue;
            }
            let Some(node) = self.index.class(c) else { continue };
            for (n, _) in self.declaredMembers(node, setters, true) {
                if seen.insert(n) {
                    names.push(n);
                }
            }
            for s in supertypesOfClass(node) {
                stack.push(s.className);
            }
        }
        names
    }
}

fn record(generic: &mut Vec<(CnId, Supertype)>, class: CnId, ty: Supertype) {
    // recordGenericSuperType: the first instantiation is canonical; a later
    // one merges with it (nnbdTopMergeSupertype), which leaves equal
    // instantiations unchanged.
    if !generic.iter().any(|(k, _)| *k == class) {
        generic.push((class, ty));
    }
}

/// `Field.isStatic`.
pub const FIELD_STATIC: u32 = 1 << 2;
/// `Procedure.isStatic`.
pub const PROCEDURE_STATIC: u32 = 1 << 0;
/// `Procedure.isAbstract`.
pub const PROCEDURE_ABSTRACT: u32 = 1 << 1;

/// `TypeParameter.computeNullabilityFromBound`.
pub fn computeNullabilityFromBound(parameter: &TypeParameter, index: &NodeIndex) -> u8 {
    let mut ty = &parameter.bound;
    while let DartType::FutureOr { typeArgument, .. } = ty {
        ty = typeArgument;
    }
    if let DartType::TypeParameter { parameter: p, .. } = ty {
        if *p == parameter.id {
            return Nullability::undetermined;
        }
    }
    let boundNullability = match &parameter.bound {
        DartType::Invalid => Nullability::undetermined,
        b => crate::type_algebra::nullability(b, index),
    };
    if boundNullability == Nullability::nullable || boundNullability == Nullability::undetermined {
        Nullability::undetermined
    } else {
        Nullability::nonNullable
    }
}
