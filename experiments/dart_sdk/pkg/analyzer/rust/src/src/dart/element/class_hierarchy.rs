// Port of lib/src/dart/element/class_hierarchy.dart: `ClassHierarchy` (the
// interfaces an interface element implements, `allSupertypes`, cached per
// element) and `InterfacesMerger` (one type per class: the first one seen,
// or the NNBD_TOP_MERGE of the NORMs when two instantiations differ, and an
// error when they cannot merge).

use std::collections::HashMap;

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::element::element::{ElementId, ElementKind, ElementStore};
use crate::src::dart::element::normalize::normalize;
use crate::src::dart::element::r#type::{type_equals, TypeImpl};
use crate::src::dart::element::top_merge::top_merge;
use crate::src::dart::element::type_algebra::{substitute, Substitution};

/// `ClassHierarchy`.
#[derive(Debug, Default)]
pub struct ClassHierarchy {
    map: HashMap<ElementId, Hierarchy>,
}

#[derive(Debug, Clone, Default)]
struct Hierarchy {
    /// The number of errors (`ClassHierarchyError`s); their details are
    /// not needed while linking.
    errors: usize,
    interfaces: Vec<TypeImpl>,
}

impl ClassHierarchy {
    /// `remove`.
    pub fn remove(&mut self, element: ElementId) {
        self.map.remove(&element);
    }

    /// `errors`: how many incompatible-interface errors [element]'s
    /// hierarchy has.
    pub fn error_count(&mut self, store: &mut ElementStore, element: ElementId) -> usize {
        self.hierarchy(store, element).errors
    }

    /// `implementedInterfaces`: `allSupertypes` of [element].
    pub fn implemented_interfaces(&mut self, store: &mut ElementStore, element: ElementId) -> Vec<TypeImpl> {
        self.hierarchy(store, element).interfaces
    }

    /// `_getHierarchy`.
    fn hierarchy(&mut self, store: &mut ElementStore, element: ElementId) -> Hierarchy {
        if let Some(h) = self.map.get(&element) {
            return h.clone();
        }
        // A placeholder breaks cycles, as upstream's empty `_Hierarchy` does.
        self.map.insert(element, Hierarchy::default());

        let mut merger = InterfacesMerger::default();
        let append = |this: &mut Self, store: &mut ElementStore, merger: &mut InterfacesMerger, t: Option<TypeImpl>| {
            let Some(t) = t else { return };
            let Some(i) = t.as_interface().cloned() else { return };
            merger.add(store, &t);
            let substitution = from_interface_type(store, i.element, &i.type_arguments);
            for raw in this.implemented_interfaces(store, i.element) {
                let new_interface = substitute(store, &substitution, &raw);
                merger.add(store, &new_interface);
            }
        };

        let kind = store.element(element).kind;
        let supertype = if kind == ElementKind::MIXIN { None } else { store.element(element).type_.clone() };
        append(self, store, &mut merger, supertype);
        let types = store.types(element).cloned().unwrap_or_default();
        if kind == ElementKind::MIXIN {
            for t in types.superclass_constraints.clone() {
                append(self, store, &mut merger, Some(t));
            }
        }
        for t in types.interfaces.clone() {
            append(self, store, &mut merger, Some(t));
        }
        for t in types.mixins.clone() {
            append(self, store, &mut merger, Some(t));
        }

        let hierarchy = Hierarchy {
            errors: merger.entries.iter().filter(|e| e.error).count(),
            interfaces: merger.entries.iter().map(|e| e.type_()).collect(),
        };
        self.map.insert(element, hierarchy.clone());
        hierarchy
    }
}

/// `Substitution.fromInterfaceType`: the class's type parameters to the
/// type's arguments.
pub fn from_interface_type(store: &ElementStore, element: ElementId, arguments: &[TypeImpl]) -> Substitution {
    let first = store.element(element).first_fragment;
    let parameters: Vec<ElementId> = store.fragment(first).type_parameters.iter().map(|&f| store.fragment(f).element).collect();
    if parameters.len() != arguments.len() {
        return Substitution::default();
    }
    Substitution::from_pairs(parameters, arguments.to_vec())
}

/// `InterfacesMerger`.
#[derive(Debug, Default)]
pub struct InterfacesMerger {
    entries: Vec<ClassInterfaceType>,
    index: HashMap<ElementId, usize>,
}

impl InterfacesMerger {
    /// `typeList`.
    pub fn type_list(&self) -> Vec<TypeImpl> {
        self.entries.iter().map(|e| e.type_()).collect()
    }

    /// `add`.
    pub fn add(&mut self, store: &mut ElementStore, t: &TypeImpl) {
        let Some(i) = t.as_interface() else { return };
        let element = i.element;
        let index = match self.index.get(&element) {
            Some(&n) => n,
            None => {
                let is_object = store.is_dart_core_class(element, "Object");
                self.entries.push(ClassInterfaceType {
                    is_dart_core_object: is_object,
                    error: false,
                    single_type: None,
                    current_result: None,
                });
                self.index.insert(element, self.entries.len() - 1);
                self.entries.len() - 1
            }
        };
        self.entries[index].update(store, t);
    }

    /// `addWithSupertypes`.
    pub fn add_with_supertypes(&mut self, store: &mut ElementStore, hierarchy: &mut ClassHierarchy, t: Option<&TypeImpl>) {
        let Some(t) = t else { return };
        let Some(i) = t.as_interface().cloned() else { return };
        // `type.allSupertypes`: the element's, substituted.
        let substitution = from_interface_type(store, i.element, &i.type_arguments);
        for raw in hierarchy.implemented_interfaces(store, i.element) {
            let s = substitute(store, &substitution, &raw);
            self.add(store, &s);
        }
        self.add(store, t);
    }
}

/// `_ClassInterfaceType`.
#[derive(Debug)]
struct ClassInterfaceType {
    is_dart_core_object: bool,
    error: bool,
    single_type: Option<TypeImpl>,
    current_result: Option<TypeImpl>,
}

impl ClassInterfaceType {
    fn type_(&self) -> TypeImpl {
        self.current_result.clone().or_else(|| self.single_type.clone()).unwrap()
    }

    /// `update`.
    fn update(&mut self, store: &mut ElementStore, t: &TypeImpl) {
        if self.error {
            return;
        }
        if self.current_result.is_none() {
            match &self.single_type {
                None => {
                    self.single_type = Some(t.clone());
                    return;
                }
                Some(single) if type_equals(store, t, single) => return,
                Some(single) => {
                    let single = single.clone();
                    self.current_result = Some(normalize(store, &single));
                }
            }
        }
        let norm_type = normalize(store, t);
        let current = self.current_result.clone().unwrap();
        match self.merge(store, &current, &norm_type) {
            Ok(r) => self.current_result = Some(r),
            Err(_) => self.error = true,
        }
    }

    /// `_merge`.
    fn merge(&self, store: &mut ElementStore, t1: &TypeImpl, t2: &TypeImpl) -> Result<TypeImpl, &'static str> {
        // Normally `Object?` cannot be a superinterface; it can for extension
        // types.
        if self.is_dart_core_object {
            let (s1, s2) = (t1.as_interface().unwrap().nullability_suffix, t2.as_interface().unwrap().nullability_suffix);
            if s1 == NullabilitySuffix::question && s2 == NullabilitySuffix::none {
                return Ok(t2.clone());
            }
            if s1 == NullabilitySuffix::none && s2 == NullabilitySuffix::question {
                return Ok(t1.clone());
            }
        }
        top_merge(store, t1, t2)
    }
}
