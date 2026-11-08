// Port of the part of lib/src/dart/element/inheritance_manager3.dart that
// `getMember3` reads for a method of an interface type: the instance method
// the interface of a class, enum, mixin or extension type has under a name,
// declared or inherited, with the receiver's type arguments substituted
// (upstream's `Member`s, here a `Member` holding the substitution).
//
// As `_getInterface` merges an interface, a declared method wins; otherwise
// the class chain (the superclass, with each mixin applied over it in order,
// a mixin's own interface taking precedence as the mixin application declares
// it) gives one candidate, and each other superinterface (implemented
// interfaces, a mixin's superclass constraints, an extension type's
// implemented types) another. Candidates with the same signature are one
// member; otherwise the member is the candidate whose function type is a
// subtype of all the others (`_findMostSpecificFromNamedCandidates`).
//
// Not ported: combined member signatures when no candidate is most specific
// (reported as `Ambiguous`, which callers treat as unresolved), getters,
// setters and fields, private names (`Name` with its library), `forSuper`,
// the extension type rules for members redeclared from non-extension-type
// superinterfaces, and conflicts and their diagnostics. Nothing is cached.

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::element::class_hierarchy::from_interface_type;
use crate::src::dart::element::element::{ElementId, ElementKind, ElementStore, FragmentFlag};
use crate::src::dart::element::r#type::{FormalParameter, FunctionTypeImpl, InterfaceTypeImpl, TypeImpl, type_equals};
use crate::src::dart::element::subtype::TypeSystem;
use crate::src::dart::element::type_algebra::{Substitution, substitute};
use crate::src::dart::element::type_system::without_builders;

/// A method of an interface with the type arguments of the type it was
/// found in (`ExecutableMember`).
#[derive(Clone, Debug)]
pub struct Member {
    pub element: ElementId,
    pub substitution: Substitution,
}

/// What [get_method] finds.
#[derive(Clone, Debug)]
pub enum MethodLookup {
    Found(Member),
    NotFound,
    /// Candidates with different signatures, none the most specific: the
    /// combined member signature upstream builds is not ported.
    Ambiguous,
}

impl Member {
    /// `returnType`, substituted.
    pub fn return_type(&self, store: &mut ElementStore) -> TypeImpl {
        let declared = built(store, store.element(self.element).type_.as_ref());
        substitute(store, &self.substitution, &declared)
    }

    /// The types of `formalParameters`, substituted.
    pub fn parameter_types(&self, store: &mut ElementStore) -> Vec<TypeImpl> {
        self.formal_parameters(store).into_iter().map(|p| p.type_).collect()
    }

    fn formal_parameters(&self, store: &mut ElementStore) -> Vec<FormalParameter> {
        let first = store.element(self.element).first_fragment;
        let fragments = store.fragment(first).formal_parameters.clone();
        fragments
            .into_iter()
            .map(|f| {
                let fragment = store.fragment(f);
                let (name, kind) = (fragment.name.clone(), fragment.parameter_kind);
                let declared = built(store, store.element(fragment.element).type_.as_ref());
                let type_ = substitute(store, &self.substitution, &declared);
                FormalParameter { name, type_, kind }
            })
            .collect()
    }

    /// `hasImplicitReturnType`, or `hasImplicitType` of a formal parameter:
    /// types override inference would infer, which is not ported.
    pub fn has_implicit_types(&self, store: &ElementStore) -> bool {
        let first = store.fragment(store.element(self.element).first_fragment);
        first.has_flag(FragmentFlag::executableFragment_hasImplicitReturnType)
            || first
                .formal_parameters
                .iter()
                .any(|&p| store.fragment(p).has_flag(FragmentFlag::variableFragment_hasImplicitType))
    }

    /// The kind of the element that declares the method.
    pub fn enclosing_kind(&self, store: &ElementStore) -> ElementKind {
        let first = store.fragment(store.element(self.element).first_fragment);
        let enclosing = store.fragment(first.enclosing_fragment).element;
        store.element(enclosing).kind
    }

    fn function_type(&self, store: &mut ElementStore) -> FunctionTypeImpl {
        let parameters = self.formal_parameters(store);
        let return_type = self.return_type(store);
        FunctionTypeImpl::new(Vec::new(), parameters, return_type, NullabilitySuffix::none)
    }
}

/// `getMember3(type, Name(name))` for the instance method [name] (with
/// `unary-` for unary minus), as [Member]s of [type_]'s interface.
pub fn get_method(system: &mut TypeSystem<'_>, type_: &InterfaceTypeImpl, name: &str) -> MethodLookup {
    interface_method(system, type_.element, &type_.type_arguments, name, &mut Vec::new())
}

fn interface_method(
    system: &mut TypeSystem<'_>,
    element: ElementId,
    arguments: &[TypeImpl],
    name: &str,
    visiting: &mut Vec<ElementId>,
) -> MethodLookup {
    if visiting.contains(&element) {
        return MethodLookup::NotFound;
    }
    let substitution = from_interface_type(system.store, element, arguments);
    let e = system.store.element(element);
    let Some(members) = e.members.as_deref() else {
        return MethodLookup::NotFound;
    };
    for &method in &members.methods {
        let fragment = system.store.fragment(system.store.element(method).first_fragment);
        if !fragment.is_static() && fragment.method_lookup_name().as_deref() == Some(name) {
            return MethodLookup::Found(Member { element: method, substitution });
        }
    }
    let kind = e.kind;
    let supertype = if matches!(kind, ElementKind::CLASS | ElementKind::ENUM) { e.type_.clone() } else { None };
    let (mixins, others) = match system.store.types(element) {
        Some(types) => {
            let mut others = types.superclass_constraints.clone();
            others.extend(types.interfaces.iter().cloned());
            (types.mixins.clone(), others)
        }
        None => (Vec::new(), Vec::new()),
    };
    visiting.push(element);
    let mut lookup = |system: &mut TypeSystem<'_>, supertype: &TypeImpl| -> MethodLookup {
        let supertype = without_builders(system.store, supertype);
        let supertype = substitute(system.store, &substitution, &supertype);
        match supertype.as_interface() {
            Some(i) => {
                let i = i.clone();
                interface_method(system, i.element, &i.type_arguments, name, visiting)
            }
            None => MethodLookup::NotFound,
        }
    };
    let mut chain = match &supertype {
        Some(supertype) => lookup(system, supertype),
        None => MethodLookup::NotFound,
    };
    for mixin in &mixins {
        let found = lookup(system, mixin);
        if !matches!(found, MethodLookup::NotFound) {
            chain = found;
        }
    }
    let mut candidates = Vec::new();
    let mut ambiguous = false;
    for found in std::iter::once(chain).chain(others.iter().map(|t| lookup(system, t)).collect::<Vec<_>>()) {
        match found {
            MethodLookup::Found(member) => candidates.push(member),
            MethodLookup::NotFound => {}
            MethodLookup::Ambiguous => ambiguous = true,
        }
    }
    visiting.pop();
    if ambiguous {
        return MethodLookup::Ambiguous;
    }
    if candidates.is_empty() {
        return MethodLookup::NotFound;
    }
    let types: Vec<FunctionTypeImpl> = candidates.iter().map(|c| c.function_type(system.store)).collect();
    let same = |a: &FunctionTypeImpl, b: &FunctionTypeImpl, store: &ElementStore| {
        a.formal_parameters.len() == b.formal_parameters.len()
            && type_equals(store, &a.return_type, &b.return_type)
            && a.formal_parameters
                .iter()
                .zip(&b.formal_parameters)
                .all(|(p, q)| p.kind == q.kind && type_equals(store, &p.type_, &q.type_))
    };
    if types.iter().all(|t| same(&types[0], t, system.store)) {
        return MethodLookup::Found(candidates.swap_remove(0));
    }
    // `_findMostSpecificFromNamedCandidates`.
    for (i, candidate) in types.iter().enumerate() {
        let candidate_type = TypeImpl::Function(std::rc::Rc::new(candidate.clone()));
        let most_specific = types.iter().enumerate().all(|(j, other)| {
            i == j || system.is_subtype_of(&candidate_type, &TypeImpl::Function(std::rc::Rc::new(other.clone())))
        });
        if most_specific {
            return MethodLookup::Found(candidates.swap_remove(i));
        }
    }
    MethodLookup::Ambiguous
}

/// The type a linked element holds, without builders; `dynamic` when none.
fn built(store: &ElementStore, type_: Option<&TypeImpl>) -> TypeImpl {
    type_.map_or(TypeImpl::Dynamic, |t| without_builders(store, t))
}
