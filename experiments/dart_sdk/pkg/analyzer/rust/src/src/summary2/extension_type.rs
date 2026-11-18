// Port of lib/src/summary2/extension_type.dart: `buildExtensionTypes`, which
// walks the extension types of the libraries being linked through the
// extension types their representation types name, and marks every cycle:
// its extension types have a representation that depends on itself, and
// their representation fields and declaring formal parameters get
// `InvalidType`.
//
// The walk is the ported `DependencyWalker`; a node is an extension type,
// numbered in the order the walk meets it (`_Walker.getNode`).
//
// Not ported: the erasure of an acyclic representation type
// (`typeErasure = type.extensionTypeErasure`, the `ExtensionTypeErasure`
// replacement visitor), which nothing in the port reads yet. A cycle's
// erasure, `InvalidType`, is set.

use std::collections::{HashMap, HashSet};

use crate::fe_analyzer_shared::util::dependency_walker::{DependencyWalker, Walk};
use crate::src::dart::element::element::{ElementId, ElementKind, ElementStore, LibraryId};
use crate::src::dart::element::r#type::TypeImpl;

/// `buildExtensionTypes`: [libraries] are the libraries being linked, and
/// [declaring_formal] maps a representation field to the formal parameter
/// that declares it (`declaringFormalParameter`).
pub fn build_extension_types(
    store: &mut ElementStore,
    libraries: &[LibraryId],
    declaring_formal: &HashMap<ElementId, ElementId>,
) {
    let linking: HashSet<LibraryId> = libraries.iter().copied().collect();
    let mut walk = ExtensionTypeWalk {
        store,
        linking: &linking,
        declaring_formal,
        nodes: Vec::new(),
        node_of: HashMap::new(),
        evaluated: Vec::new(),
    };
    let mut nodes = Vec::new();
    for &library in libraries {
        for e in walk.store.libraries[library as usize].extension_types.clone() {
            nodes.push(walk.node(e));
        }
    }
    let mut walker = DependencyWalker::default();
    for node in nodes {
        walker.walk(&mut walk, node);
    }
}

/// `_Walker` and its `_Node`s.
struct ExtensionTypeWalk<'a> {
    store: &'a mut ElementStore,
    linking: &'a HashSet<LibraryId>,
    declaring_formal: &'a HashMap<ElementId, ElementId>,
    nodes: Vec<ElementId>,
    node_of: HashMap<ElementId, usize>,
    evaluated: Vec<bool>,
}

impl ExtensionTypeWalk<'_> {
    /// `_Walker.getNode`.
    fn node(&mut self, element: ElementId) -> usize {
        if let Some(&node) = self.node_of.get(&element) {
            return node;
        }
        let node = self.nodes.len();
        self.nodes.push(element);
        self.evaluated.push(false);
        self.node_of.insert(element, node);
        node
    }

    /// `element.representation`: the first field.
    fn representation(&self, element: ElementId) -> Option<ElementId> {
        self.store.element(element).members().fields.first().copied()
    }

    /// `element.representation.type`.
    fn representation_type(&mut self, element: ElementId) -> Option<TypeImpl> {
        let field = self.representation(element)?;
        self.store.property_inducing_type(field)
    }

    /// `_Node._markCircular`.
    fn mark_circular(&mut self, node: usize) {
        let element = self.nodes[node];
        self.store.types_mut(element).has_representation_self_reference = true;
        if let Some(field) = self.representation(element) {
            self.store.set_property_inducing_type(field, TypeImpl::Invalid);
            if let Some(&formal) = self.declaring_formal.get(&field) {
                self.store.elements[formal as usize].type_ = Some(TypeImpl::Invalid);
            }
        }
        // `_evaluateWithType(InvalidTypeImpl.instance)`.
        self.store.types_mut(element).type_erasure = Some(TypeImpl::Invalid);
        self.evaluated[node] = true;
    }
}

/// `_DependenciesCollector`, a `RecursiveTypeVisitor` with
/// `includeTypeAliasArguments: false`: the extension types [type_] names.
fn collect_dependencies(store: &ElementStore, type_: &TypeImpl, dependencies: &mut Vec<ElementId>) {
    match type_ {
        TypeImpl::Interface(i) => {
            if store.element(i.element).kind == ElementKind::EXTENSION_TYPE {
                dependencies.push(i.element);
            }
            for argument in &i.type_arguments {
                collect_dependencies(store, argument, dependencies);
            }
        }
        TypeImpl::Function(f) => {
            collect_dependencies(store, &f.return_type, dependencies);
            for &type_parameter in &f.type_parameters {
                if let Some(bound) = &store.element(type_parameter).type_ {
                    collect_dependencies(store, bound, dependencies);
                }
            }
            for formal_parameter in &f.formal_parameters {
                collect_dependencies(store, &formal_parameter.type_, dependencies);
            }
        }
        TypeImpl::Record(r) => {
            for field in &r.positional_fields {
                collect_dependencies(store, field, dependencies);
            }
            for (_, field) in &r.named_fields {
                collect_dependencies(store, field, dependencies);
            }
        }
        // `visitTypeParameterType` does not visit the bound.
        _ => {}
    }
}

impl Walk for ExtensionTypeWalk<'_> {
    fn is_evaluated(&self, node: usize) -> bool {
        self.evaluated[node]
    }

    /// `_Node.computeDependencies`.
    fn compute_dependencies(&mut self, node: usize) -> Vec<usize> {
        let element = self.nodes[node];
        let mut elements = Vec::new();
        if let Some(t) = self.representation_type(element) {
            collect_dependencies(self.store, &t, &mut elements);
        }
        let mut dependencies = Vec::new();
        for e in elements {
            let library = self.store.element(e).library;
            // `walker.linker.isLinkingElement(element)`.
            if self.linking.contains(&library) {
                dependencies.push(self.node(e));
            }
        }
        dependencies
    }

    /// `_Node._evaluate`: reads the representation type (and would erase
    /// it; see above).
    fn evaluate(&mut self, node: usize) {
        let element = self.nodes[node];
        self.representation_type(element);
        self.evaluated[node] = true;
    }

    /// `_Walker.evaluateScc`.
    fn evaluate_scc(&mut self, scc: &[usize]) {
        for &node in scc {
            self.mark_circular(node);
        }
    }
}
