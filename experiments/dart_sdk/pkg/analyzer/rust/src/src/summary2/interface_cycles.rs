// Port of lib/src/summary2/interface_cycles.dart: `breakInterfaceCycles`,
// which finds the interface elements whose supertype, mixins, interfaces or
// superclass constraints lead back to themselves, and clears them: a class
// gets `Object` as its supertype, a mixin `Object` as its constraint, an
// extension type `Object` or `Object?` as its interface.

use std::collections::HashMap;

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::fe_analyzer_shared::util::dependency_walker::{DependencyWalker, Walk};
use crate::src::dart::element::element::{ElementId, ElementKind, ElementStore};
use crate::src::dart::element::r#type::TypeImpl;

/// `breakInterfaceCycles`, for the interface elements the declarations
/// being linked declare.
pub fn break_interface_cycles(store: &mut ElementStore, elements: &[ElementId]) {
    let mut walk = ImplementsWalk {
        store,
        nodes: Vec::new(),
        node_of: HashMap::new(),
        evaluated: Vec::new(),
    };
    let mut walker = DependencyWalker::default();
    for &element in elements {
        let node = walk.node(element);
        walker.walk(&mut walk, node);
    }
}

fn is_interface(kind: ElementKind) -> bool {
    matches!(kind, ElementKind::CLASS | ElementKind::ENUM | ElementKind::MIXIN | ElementKind::EXTENSION_TYPE)
}

/// `_ImplementsWalker` with its `_ImplementsNode`s, numbered.
struct ImplementsWalk<'s> {
    store: &'s mut ElementStore,
    nodes: Vec<ElementId>,
    node_of: HashMap<ElementId, usize>,
    evaluated: Vec<bool>,
}

impl ImplementsWalk<'_> {
    /// `getNode`.
    fn node(&mut self, element: ElementId) -> usize {
        if let Some(&n) = self.node_of.get(&element) {
            return n;
        }
        let n = self.nodes.len();
        self.nodes.push(element);
        self.evaluated.push(false);
        self.node_of.insert(element, n);
        n
    }

    /// `_markCircular`.
    fn mark_circular(&mut self, node: usize) {
        self.evaluated[node] = true;
        let element = self.nodes[node];
        let store = &mut *self.store;
        store.types_mut(element).interface_cycle = true;
        let object = store.dart_core_object();
        let object_type = |suffix| object.map(|o| TypeImpl::interface(o, Vec::new(), suffix));
        match store.element(element).kind {
            ElementKind::CLASS => {
                store.elements[element as usize].type_ = object_type(NullabilitySuffix::none);
                store.types_mut(element).mixins = Vec::new();
                store.types_mut(element).interfaces = Vec::new();
            }
            ElementKind::ENUM => {
                store.types_mut(element).mixins = Vec::new();
                store.types_mut(element).interfaces = Vec::new();
            }
            ElementKind::EXTENSION_TYPE => {
                store.types_mut(element).has_implements_self_reference = true;
                let representation = store
                    .element(element)
                    .members()
                    .fields
                    .first()
                    .and_then(|&f| store.element(f).type_.clone());
                let suffix = if representation.as_ref().is_some_and(|t| is_non_nullable(store, t)) {
                    NullabilitySuffix::none
                } else {
                    NullabilitySuffix::question
                };
                store.types_mut(element).interfaces = object_type(suffix).into_iter().collect();
            }
            ElementKind::MIXIN => {
                store.types_mut(element).superclass_constraints =
                    object_type(NullabilitySuffix::none).into_iter().collect();
                store.types_mut(element).interfaces = Vec::new();
            }
            _ => {}
        }
    }
}

/// `TypeSystemImpl.isNonNullable`, for the types a representation can have
/// while linking.
fn is_non_nullable(store: &ElementStore, t: &TypeImpl) -> bool {
    match t {
        TypeImpl::Dynamic | TypeImpl::Void | TypeImpl::Invalid => false,
        TypeImpl::Never(suffix) => *suffix == NullabilitySuffix::none,
        TypeImpl::Interface(i) => {
            i.nullability_suffix == NullabilitySuffix::none
                && !store.is_dart_core_null(i.element)
                && !(store.is_dart_core_class(i.element, "FutureOr")
                    && i.type_arguments.first().is_some_and(|a| !is_non_nullable(store, a)))
        }
        TypeImpl::TypeParameter(p) => {
            p.nullability_suffix == NullabilitySuffix::none
                && store.element(p.element).type_.as_ref().is_some_and(|b| is_non_nullable(store, b))
        }
        TypeImpl::Function(f) => f.nullability_suffix == NullabilitySuffix::none,
        TypeImpl::Record(r) => r.nullability_suffix == NullabilitySuffix::none,
        TypeImpl::Builder(_) => false,
    }
}

impl Walk for ImplementsWalk<'_> {
    fn is_evaluated(&self, node: usize) -> bool {
        self.evaluated[node]
    }

    /// `_ImplementsNode.computeDependencies`.
    fn compute_dependencies(&mut self, node: usize) -> Vec<usize> {
        let element = self.nodes[node];
        let mut types: Vec<TypeImpl> = Vec::new();
        let e = self.store.element(element);
        if e.kind != ElementKind::MIXIN {
            types.extend(e.type_.clone());
        }
        if let Some(t) = self.store.types(element) {
            types.extend(t.mixins.iter().cloned());
            types.extend(t.interfaces.iter().cloned());
            if e.kind == ElementKind::MIXIN {
                types.extend(t.superclass_constraints.iter().cloned());
            }
        }
        types
            .iter()
            .filter_map(|t| t.as_interface().map(|i| i.element))
            .filter(|&el| is_interface(self.store.element(el).kind))
            .collect::<Vec<_>>()
            .into_iter()
            .map(|el| self.node(el))
            .collect()
    }

    fn evaluate(&mut self, node: usize) {
        self.evaluated[node] = true;
    }

    /// `evaluateScc`: every node of a cycle is circular.
    fn evaluate_scc(&mut self, scc: &[usize]) {
        for &node in scc {
            self.mark_circular(node);
        }
    }
}
