// Port of lib/src/dart/element/scope.dart: the scopes the linker resolves
// type annotations in. `LibraryFragmentScope` (the library's declarations,
// then the file's import prefixes, then its imports, then those of the file
// that includes it), `PrefixScope` (the names an import or a group of
// imports with one prefix provides, merged into `MultiplyDefinedElement`s
// when they conflict), `LibraryDeclarations`, `EnclosedScope` with
// `TypeParameterScope`, `InstanceScope` and `ExtensionScope`.
//
// The scopes live in a `Scopes` arena owned by the linker and are named by
// `ScopeId`s, as upstream's objects reference their parents.
//
// Not ported: doc import scopes, local, formal parameter, constructor
// initializer and primary parameter scopes (only bodies and initializers use
// them, which linking does not resolve), imports tracking, deprecated-export
// bits, private declarations of imported libraries, and requirement
// recording.

use std::collections::HashMap;
use std::rc::Rc;

use crate::src::dart::element::element::{
    DirectiveUri, ElementId, ElementKind, ElementStore, LibraryId, NamespaceCombinator, UnitId, DYNAMIC_ELEMENT,
    NEVER_ELEMENT,
};
use crate::src::dart::resolver::scope::create_namespace_for_directive;

/// What a scope lookup finds under one name.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ScopeElement {
    Element(ElementId),
    /// `PrefixElementImpl`: an import prefix of a file, with its scope.
    Prefix(PrefixId),
    /// `MultiplyDefinedElementImpl`: conflicting imported elements.
    MultiplyDefined(Rc<[ElementId]>),
    /// `loadLibraryFunction` of a deferred import.
    LoadLibrary(LibraryId),
}

/// `ScopeLookupResultImpl`.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ScopeLookupResult {
    pub getter: Option<ScopeElement>,
    pub setter: Option<ScopeElement>,
}

pub type PrefixId = u32;
pub type PrefixScopeId = u32;

/// A scope: a file's `LibraryFragmentScope`, or an `EnclosedScope`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScopeId {
    LibraryFragment(UnitId),
    Enclosed(u32),
}

/// `PrefixElementImpl`.
#[derive(Clone, Debug)]
pub struct PrefixElement {
    pub name: Rc<str>,
    pub is_deferred: bool,
    pub scope: PrefixScopeId,
}

#[derive(Clone, Debug, Default)]
struct GettersAndSetters {
    getters: HashMap<Rc<str>, ScopeElement>,
    setters: HashMap<Rc<str>, ScopeElement>,
}

/// `PrefixScope`.
#[derive(Clone, Debug, Default)]
struct PrefixScope {
    names: GettersAndSetters,
    parent: Option<PrefixScopeId>,
    /// `_deferredLibrary`: `loadLibrary` resolves to its function.
    deferred_library: Option<LibraryId>,
}

/// The `LibraryFragmentScope` of a file.
#[derive(Clone, Debug, Default)]
struct FragmentScope {
    library: LibraryId,
    enclosing: Option<UnitId>,
    prefixes: HashMap<Rc<str>, PrefixId>,
    no_prefix: PrefixScopeId,
    wildcard_variables: bool,
}

/// An `EnclosedScope`; `InstanceScope` when [instance] is set.
#[derive(Clone, Debug)]
struct EnclosedScope {
    parent: ScopeId,
    names: GettersAndSetters,
    instance: bool,
}

/// The scopes of a library cycle being linked.
#[derive(Debug, Default)]
pub struct Scopes {
    library_declarations: HashMap<LibraryId, GettersAndSetters>,
    fragments: HashMap<UnitId, FragmentScope>,
    prefix_scopes: Vec<PrefixScope>,
    pub prefixes: Vec<PrefixElement>,
    enclosed: Vec<EnclosedScope>,
}

/// The language features the scopes depend on, from the library's feature
/// set.
#[derive(Clone, Copy, Debug)]
pub struct ScopeFeatures {
    pub wildcard_variables: bool,
    pub records: bool,
}

fn add_getter(names: &mut GettersAndSetters, store: &ElementStore, element: ElementId) {
    // `lookupName`.
    if let Some(name) = store.element(element).name.clone() {
        names.getters.entry(name).or_insert(ScopeElement::Element(element));
    }
}

fn add_setter(names: &mut GettersAndSetters, store: &ElementStore, element: ElementId) {
    // A setter's `lookupName` is its name with `=`, which `_addSetter` strips.
    if let Some(name) = store.element(element).name.clone() {
        names.setters.entry(name).or_insert(ScopeElement::Element(element));
    }
}

impl Scopes {
    /// `LibraryDeclarations` of [library], made once.
    fn library_declarations(&mut self, store: &ElementStore, library: LibraryId) {
        if self.library_declarations.contains_key(&library) {
            return;
        }
        let l = &store.libraries[library as usize];
        let mut names = GettersAndSetters::default();
        for list in [&l.getters, &l.enums, &l.extensions, &l.extension_types] {
            for &e in list.iter() {
                add_getter(&mut names, store, e);
            }
        }
        for &e in &l.setters {
            add_setter(&mut names, store, e);
        }
        for list in [&l.top_level_functions, &l.type_aliases, &l.mixins, &l.classes] {
            for &e in list.iter() {
                add_getter(&mut names, store, e);
            }
        }
        // Implicit `dart:core` declarations.
        if &*l.uri == "dart:core" {
            add_getter(&mut names, store, DYNAMIC_ELEMENT);
            add_getter(&mut names, store, NEVER_ELEMENT);
        }
        self.library_declarations.insert(library, names);
    }

    /// `LibraryFragmentScope(libraryFragment)`, with the scopes of its
    /// prefixes. The file that includes [unit] (if any) must have its scope
    /// already.
    pub fn add_library_fragment(
        &mut self,
        store: &ElementStore,
        unit: UnitId,
        enclosing: Option<UnitId>,
        features: ScopeFeatures,
    ) {
        let library = store.units[unit as usize].library;
        self.library_declarations(store, library);
        let imports = store.units[unit as usize].library_imports.clone();
        let no_prefix = self.add_prefix_scope(store, library, &imports, None, None, features);

        // `libraryFragment.prefixes`: one element per prefix name.
        let mut prefixes: HashMap<Rc<str>, PrefixId> = HashMap::new();
        let mut order: Vec<Rc<str>> = Vec::new();
        let mut deferred: HashMap<Rc<str>, bool> = HashMap::new();
        for import in &imports {
            if let Some(prefix) = &import.prefix {
                if let Some(name) = &prefix.name {
                    if !deferred.contains_key(name) {
                        order.push(name.clone());
                    }
                    let d = deferred.entry(name.clone()).or_insert(false);
                    *d = *d || prefix.is_deferred;
                }
            }
        }
        self.fragments.insert(
            unit,
            FragmentScope {
                library,
                enclosing,
                prefixes: HashMap::new(),
                no_prefix,
                wildcard_variables: features.wildcard_variables,
            },
        );
        // `_buildPrefixScopes`.
        for name in order {
            let is_deferred = deferred[&name];
            let parent = if is_deferred { None } else { self.parent_prefix_scope(unit, &name) };
            let scope = self.add_prefix_scope(store, library, &imports, Some(&name), parent, features);
            let id = self.prefixes.len() as PrefixId;
            self.prefixes.push(PrefixElement {
                name: name.clone(),
                is_deferred,
                scope,
            });
            prefixes.insert(name, id);
        }
        self.fragments.get_mut(&unit).unwrap().prefixes = prefixes;
    }

    /// `_getParentPrefixScope`: the scope of the same prefix in the nearest
    /// enclosing file that has it, unless a file in between imports the name
    /// without a prefix.
    fn parent_prefix_scope(&self, unit: UnitId, name: &Rc<str>) -> Option<PrefixScopeId> {
        let mut scope = self.fragments[&unit].enclosing;
        while let Some(u) = scope {
            let f = &self.fragments[&u];
            if let Some(&parent) = f.prefixes.get(name) {
                let p = &self.prefixes[parent as usize];
                return if p.is_deferred { None } else { Some(p.scope) };
            }
            let np = &self.prefix_scopes[f.no_prefix as usize].names;
            if np.getters.contains_key(name) || np.setters.contains_key(name) {
                break;
            }
            scope = f.enclosing;
        }
        None
    }

    /// `PrefixScope(...)`: the imports of the file with [prefix].
    fn add_prefix_scope(
        &mut self,
        store: &ElementStore,
        library: LibraryId,
        imports: &[crate::src::dart::element::element::LibraryImportImpl],
        prefix: Option<&Rc<str>>,
        parent: Option<PrefixScopeId>,
        features: ScopeFeatures,
    ) -> PrefixScopeId {
        let mut scope = PrefixScope {
            parent,
            ..PrefixScope::default()
        };
        for import in imports {
            let DirectiveUri::WithLibrary { library: imported, .. } = &import.uri else {
                continue;
            };
            let import_prefix = import.prefix.as_ref().and_then(|p| p.name.as_ref());
            if import_prefix != prefix {
                continue;
            }
            let combinators: &[NamespaceCombinator] = &import.combinators;
            for (_, element) in create_namespace_for_directive(store, *imported, combinators) {
                if should_add(store, *imported, element, features) {
                    add_to_prefix_scope(&mut scope.names, store, element);
                }
            }
            if let Some(p) = &import.prefix {
                if p.is_deferred && scope.deferred_library.is_none() {
                    scope.deferred_library = Some(*imported);
                }
            }
        }
        let _ = library;
        let id = self.prefix_scopes.len() as PrefixScopeId;
        self.prefix_scopes.push(scope);
        id
    }

    /// `TypeParameterScope`.
    pub fn type_parameter_scope(
        &mut self,
        store: &ElementStore,
        parent: ScopeId,
        elements: &[ElementId],
        features: ScopeFeatures,
    ) -> ScopeId {
        let mut names = GettersAndSetters::default();
        for &e in elements {
            if features.wildcard_variables && store.element(e).name.as_deref() == Some("_") {
                continue;
            }
            add_getter(&mut names, store, e);
        }
        self.push_enclosed(parent, names, false)
    }

    /// `InstanceScope` (and, with [instance] false, `ExtensionScope`).
    pub fn instance_scope(&mut self, store: &ElementStore, parent: ScopeId, element: ElementId, instance: bool) -> ScopeId {
        let mut names = GettersAndSetters::default();
        let members = store.element(element).members();
        for &e in &members.getters {
            add_getter(&mut names, store, e);
        }
        for &e in &members.setters {
            add_setter(&mut names, store, e);
        }
        for &e in &members.methods {
            add_getter(&mut names, store, e);
        }
        self.push_enclosed(parent, names, instance)
    }

    fn push_enclosed(&mut self, parent: ScopeId, names: GettersAndSetters, instance: bool) -> ScopeId {
        let id = self.enclosed.len() as u32;
        self.enclosed.push(EnclosedScope { parent, names, instance });
        ScopeId::Enclosed(id)
    }

    /// `Scope.lookup`.
    pub fn lookup(&self, store: &ElementStore, scope: ScopeId, id: &str) -> ScopeLookupResult {
        match scope {
            ScopeId::Enclosed(i) => {
                let s = &self.enclosed[i as usize];
                let getter = s.names.getters.get(id).cloned();
                let setter = s.names.setters.get(id).cloned();
                if getter.is_none() && setter.is_none() {
                    return self.lookup(store, s.parent, id);
                }
                if !s.instance || is_static(store, &getter) || is_static(store, &setter) {
                    return ScopeLookupResult { getter, setter };
                }
                // An instance member: the lexical lookup yields nothing.
                ScopeLookupResult::default()
            }
            ScopeId::LibraryFragment(unit) => {
                let f = &self.fragments[&unit];
                let declarations = &self.library_declarations[&f.library];
                let getter = declarations.getters.get(id).cloned();
                let setter = declarations.setters.get(id).cloned();
                if getter.is_some() || setter.is_some() {
                    return ScopeLookupResult { getter, setter };
                }
                self.lookup_combined(unit, id).unwrap_or_default()
            }
        }
    }

    /// `_lookupCombined`.
    fn lookup_combined(&self, unit: UnitId, id: &str) -> Option<ScopeLookupResult> {
        let f = &self.fragments[&unit];
        // `isAllowedAsPrefixName`.
        let allowed = id != "_" || !f.wildcard_variables;
        if allowed {
            if let Some(&prefix) = f.prefixes.get(id) {
                return Some(ScopeLookupResult {
                    getter: Some(ScopeElement::Prefix(prefix)),
                    setter: None,
                });
            }
        }
        let result = self.lookup_prefix_scope(f.no_prefix, id);
        if result.getter.is_some() || result.setter.is_some() {
            return Some(result);
        }
        f.enclosing.and_then(|e| self.lookup_combined(e, id))
    }

    /// `PrefixScope.lookup`, for the scope of a prefix element.
    pub fn lookup_prefix(&self, prefix: PrefixId, id: &str) -> ScopeLookupResult {
        self.lookup_prefix_scope(self.prefixes[prefix as usize].scope, id)
    }

    fn lookup_prefix_scope(&self, scope: PrefixScopeId, id: &str) -> ScopeLookupResult {
        let s = &self.prefix_scopes[scope as usize];
        if s.deferred_library.is_some() && id == "loadLibrary" {
            return ScopeLookupResult {
                getter: Some(ScopeElement::LoadLibrary(s.deferred_library.unwrap())),
                setter: None,
            };
        }
        let getter = s.names.getters.get(id).cloned();
        let setter = s.names.setters.get(id).cloned();
        if getter.is_some() || setter.is_some() {
            return ScopeLookupResult { getter, setter };
        }
        match s.parent {
            Some(parent) => self.lookup_prefix_scope(parent, id),
            None => ScopeLookupResult::default(),
        }
    }
}

/// `InstanceScope._isStatic`.
fn is_static(store: &ElementStore, element: &Option<ScopeElement>) -> bool {
    let Some(ScopeElement::Element(e)) = element else {
        return false;
    };
    let e = store.element(*e);
    match e.kind {
        ElementKind::GETTER | ElementKind::SETTER | ElementKind::METHOD => store.fragment(e.first_fragment).is_static(),
        _ => false,
    }
}

/// `PrefixScope._shouldAdd`: without records, `dart:core`'s `Record` is not
/// imported.
fn should_add(store: &ElementStore, imported: LibraryId, element: ElementId, features: ScopeFeatures) -> bool {
    if !features.records {
        let in_sdk = store.libraries[imported as usize].uri.starts_with("dart:");
        if in_sdk && store.element(element).kind == ElementKind::CLASS && store.is_dart_core_class(element, "Record") {
            return false;
        }
    }
    true
}

/// `PrefixScope._add` and `_addTo`: by `displayName`, merging conflicts.
fn add_to_prefix_scope(names: &mut GettersAndSetters, store: &ElementStore, element: ElementId) {
    let Some(id) = store.element(element).name.clone() else {
        return;
    };
    let map = if store.element(element).kind == ElementKind::SETTER {
        &mut names.setters
    } else {
        &mut names.getters
    };
    let new = ScopeElement::Element(element);
    match map.get(&id) {
        None => {
            map.insert(id, new);
        }
        Some(existing) if *existing == new => {}
        Some(existing) => {
            let merged = merge(store, existing.clone(), element);
            map.insert(id, merged);
        }
    }
}

/// `PrefixScope._merge`: an SDK element loses to a non-SDK one; otherwise a
/// `MultiplyDefinedElement` of both.
fn merge(store: &ElementStore, existing: ScopeElement, other: ElementId) -> ScopeElement {
    let is_sdk = |e: &ScopeElement| match e {
        ScopeElement::Element(id) => *id == DYNAMIC_ELEMENT || *id == NEVER_ELEMENT || store.is_in_sdk(*id),
        _ => false,
    };
    let other_element = ScopeElement::Element(other);
    if is_sdk(&existing) {
        if !is_sdk(&other_element) {
            return other_element;
        }
    } else if is_sdk(&other_element) {
        return existing;
    }
    let mut conflicting: Vec<ElementId> = Vec::new();
    for e in [existing, other_element] {
        match e {
            ScopeElement::MultiplyDefined(list) => {
                for &x in list.iter() {
                    if !conflicting.contains(&x) {
                        conflicting.push(x);
                    }
                }
            }
            ScopeElement::Element(x) => {
                if !conflicting.contains(&x) {
                    conflicting.push(x);
                }
            }
            ScopeElement::Prefix(_) | ScopeElement::LoadLibrary(_) => {}
        }
    }
    ScopeElement::MultiplyDefined(Rc::from(conflicting))
}
