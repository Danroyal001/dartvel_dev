// Port of the part of lib/src/dart/element/inheritance_manager3.dart that
// `getMember3` reads for a method or getter of an interface type: the instance
// method or getter (a field's getter included) the interface of a class, enum,
// mixin or extension type has under a name,
// declared or inherited, with the receiver's type arguments substituted
// (upstream's `Member`s, here a `Member` holding the substitution).
//
// As `_getInterface` merges an interface, a declared method wins; otherwise
// the class chain (the superclass, with each mixin applied over it in order:
// a member the mixin declares replaces the member so far, one its interface
// inherits is merged with it, as `_getInterfaceClass` does) gives one candidate, and each other superinterface (implemented
// interfaces, a mixin's superclass constraints, an extension type's
// implemented types) another. Candidates with the same signature are one
// member; otherwise the member is the candidate whose function type is a
// subtype of all the others (`_findMostSpecificFromNamedCandidates`).
//
// When several candidates are valid overrides of different types, the member
// has their top merge (`_topMerge`, [Member::combined]).
//
// Not ported: candidates none of which is a valid override (reported as
// `Ambiguous`, which callers treat as unresolved), a method
// and a getter of one name (also `Ambiguous`), setters, private names (`Name` with its library), `forSuper`,
// the extension type rules for members redeclared from non-extension-type
// superinterfaces, and conflicts and their diagnostics. Nothing is cached.

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::element::class_hierarchy::from_interface_type;
use crate::src::dart::element::element::{ElementId, ElementKind, ElementStore, FragmentFlag};
use crate::src::dart::element::r#type::{FormalParameter, FunctionTypeImpl, InterfaceTypeImpl, TypeImpl, type_equals};
use crate::src::dart::element::subtype::TypeSystem;
use crate::src::dart::element::type_algebra::{Substitution, substitute};
use crate::src::dart::element::normalize::normalize;
use crate::src::dart::element::top_merge::top_merge;
use crate::src::dart::element::type_system::without_builders;
use std::rc::Rc;

/// A method of an interface with the type arguments of the type it was
/// found in (`ExecutableMember`).
#[derive(Clone, Debug)]
pub struct Member {
    pub element: ElementId,
    pub substitution: Substitution,
    /// The signature `_topMerge` combined from candidates none of whose types
    /// is it (upstream synthesizes a member with it in the target class);
    /// [element] is then the first candidate.
    pub combined: Option<Rc<FunctionTypeImpl>>,
}

/// What [get_method] finds.
#[derive(Clone, Debug)]
pub enum MethodLookup {
    Found(Member),
    NotFound,
    /// Candidates none of which is a valid override, or a method and a
    /// getter: a conflict.
    Ambiguous,
}

impl Member {
    /// `returnType`, substituted.
    pub fn return_type(&self, store: &mut ElementStore) -> TypeImpl {
        if let Some(combined) = &self.combined {
            return combined.return_type.clone();
        }
        let declared = built(store, store.element(self.element).type_.as_ref());
        substitute(store, &self.substitution, &declared)
    }

    /// The types of `formalParameters`, substituted.
    pub fn parameter_types(&self, store: &mut ElementStore) -> Vec<TypeImpl> {
        self.formal_parameters(store).into_iter().map(|p| p.type_).collect()
    }

    /// `formalParameters`, substituted.
    pub fn formal_parameters(&self, store: &mut ElementStore) -> Vec<FormalParameter> {
        if let Some(combined) = &self.combined {
            return combined.formal_parameters.clone();
        }
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
        if self.combined.is_some() {
            return false;
        }
        let first = store.fragment(store.element(self.element).first_fragment);
        first.has_flag(FragmentFlag::executableFragment_hasImplicitReturnType)
            || first
                .formal_parameters
                .iter()
                .any(|&p| store.fragment(p).has_flag(FragmentFlag::variableFragment_hasImplicitType))
    }

    /// The element that declares the member (`enclosingElement`).
    pub fn declaring_element(&self, store: &ElementStore) -> ElementId {
        let first = store.fragment(store.element(self.element).first_fragment);
        store.fragment(first.enclosing_fragment).element
    }

    /// The kind of the element that declares the method.
    pub fn enclosing_kind(&self, store: &ElementStore) -> ElementKind {
        let first = store.fragment(store.element(self.element).first_fragment);
        let enclosing = store.fragment(first.enclosing_fragment).element;
        store.element(enclosing).kind
    }

    /// `type`, substituted: the type of a method torn off (with no type
    /// parameters: generic methods are not looked up for it), and of a getter
    /// as a function of no parameters, to compare signatures.
    pub fn function_type(&self, store: &mut ElementStore) -> FunctionTypeImpl {
        let parameters = self.formal_parameters(store);
        let return_type = self.return_type(store);
        FunctionTypeImpl::new(Vec::new(), parameters, return_type, NullabilitySuffix::none)
    }
}

/// `getMember3(type, Name(name))` for the instance method [name] (with
/// `unary-` for unary minus), as [Member]s of [type_]'s interface.
pub fn get_method(system: &mut TypeSystem<'_>, type_: &InterfaceTypeImpl, name: &str) -> MethodLookup {
    interface_method(system, type_.element, &type_.type_arguments, name, false, &mut Vec::new())
}

/// `getMember3(type, Name(name))` for the instance method or getter [name]
/// (a field's getter included), as [Member]s of [type_]'s interface. A method
/// and a getter of that name in two superinterfaces are a conflict, which is
/// not ported and reported as `Ambiguous`.
pub fn get_member(system: &mut TypeSystem<'_>, type_: &InterfaceTypeImpl, name: &str) -> MethodLookup {
    interface_method(system, type_.element, &type_.type_arguments, name, true, &mut Vec::new())
}

/// The member [name] of the interface of [element] instantiated with
/// [arguments]: a method, or with [getters] also a getter.
fn interface_method(
    system: &mut TypeSystem<'_>,
    element: ElementId,
    arguments: &[TypeImpl],
    name: &str,
    getters: bool,
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
    let getter_list: &[ElementId] = if getters { &members.getters } else { &[] };
    for &method in members.methods.iter().chain(getter_list) {
        let fragment = system.store.fragment(system.store.element(method).first_fragment);
        if !fragment.is_static() && fragment.method_lookup_name().as_deref() == Some(name) {
            return MethodLookup::Found(Member { element: method, substitution, combined: None });
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
                interface_method(system, i.element, &i.type_arguments, name, getters, visiting)
            }
            None => MethodLookup::NotFound,
        }
    };
    let mut chain = match &supertype {
        Some(supertype) => lookup(system, supertype),
        None => MethodLookup::NotFound,
    };
    // `_getInterfaceClass`: each mixin replaces the member with one it
    // declares itself; a member its interface only inherits is merged with
    // the member so far, the most specific winning.
    for mixin in &mixins {
        let found = lookup(system, mixin);
        let mixin_element = without_builders(system.store, mixin).as_interface().map(|i| i.element);
        chain = match (chain, found) {
            (chain, MethodLookup::NotFound) => chain,
            (MethodLookup::NotFound, found) => found,
            (_, MethodLookup::Found(member)) if Some(member.declaring_element(system.store)) == mixin_element => {
                MethodLookup::Found(member)
            }
            (MethodLookup::Found(current), MethodLookup::Found(member)) => merge(system, vec![current, member]),
            _ => MethodLookup::Ambiguous,
        };
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
    merge(system, candidates)
}

/// One member from [candidates] (not empty) of one name, as
/// `_combineSignatures` makes it: the first when their signatures are the
/// same; else of the valid overrides (the candidates whose type is a subtype
/// of all the others', `_getValidOverrides`) the only one, the first when
/// their types are the same, or else the one whose type is the top merge of
/// their normalized types (`_topMerge`), and failing that a member with that
/// type ([Member::combined]). `Ambiguous` when there is no valid override, or
/// when a method and a getter conflict.
fn merge(system: &mut TypeSystem<'_>, mut candidates: Vec<Member>) -> MethodLookup {
    let kind = system.store.element(candidates[0].element).kind;
    if candidates.iter().any(|c| system.store.element(c.element).kind != kind) {
        return MethodLookup::Ambiguous;
    }
    let types: Vec<FunctionTypeImpl> = candidates.iter().map(|c| c.function_type(system.store)).collect();
    if types.iter().all(|t| same_signature(system.store, &types[0], t)) {
        return MethodLookup::Found(candidates.swap_remove(0));
    }
    let function = |t: &FunctionTypeImpl| TypeImpl::Function(Rc::new(t.clone()));
    let valid: Vec<usize> = (0..types.len())
        .filter(|&i| (0..types.len()).all(|j| system.is_subtype_of(&function(&types[i]), &function(&types[j]))))
        .collect();
    match valid.as_slice() {
        [] => return MethodLookup::Ambiguous,
        &[only] => return MethodLookup::Found(candidates.swap_remove(only)),
        _ => {}
    }
    let first = valid[0];
    if valid.iter().all(|&i| same_signature(system.store, &types[first], &types[i])) {
        return MethodLookup::Found(candidates.swap_remove(first));
    }
    // `_topMergeSignatureTypes`.
    let mut merged = normalize(system.store, &function(&types[first]));
    for &i in &valid[1..] {
        let next = normalize(system.store, &function(&types[i]));
        merged = match top_merge(system.store, &merged, &next) {
            Ok(merged) => merged,
            Err(_) => return MethodLookup::Ambiguous,
        };
    }
    let TypeImpl::Function(merged) = merged else {
        return MethodLookup::Ambiguous;
    };
    if let Some(&i) = valid.iter().find(|&&i| same_signature(system.store, &types[i], &merged)) {
        return MethodLookup::Found(candidates.swap_remove(i));
    }
    let mut member = candidates.swap_remove(first);
    member.combined = Some(merged);
    MethodLookup::Found(member)
}

/// Whether two signatures have the same return and parameter types and
/// parameter kinds.
fn same_signature(store: &ElementStore, a: &FunctionTypeImpl, b: &FunctionTypeImpl) -> bool {
    a.formal_parameters.len() == b.formal_parameters.len()
        && type_equals(store, &a.return_type, &b.return_type)
        && a.formal_parameters
            .iter()
            .zip(&b.formal_parameters)
            .all(|(p, q)| p.kind == q.kind && type_equals(store, &p.type_, &q.type_))
}

/// The type a linked element holds, without builders; `dynamic` when none.
fn built(store: &ElementStore, type_: Option<&TypeImpl>) -> TypeImpl {
    type_.map_or(TypeImpl::Dynamic, |t| without_builders(store, t))
}
