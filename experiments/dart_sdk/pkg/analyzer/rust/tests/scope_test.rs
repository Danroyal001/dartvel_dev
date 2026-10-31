// Not an upstream file: tests of the port of scope.dart's lookup rules
// (`LibraryFragmentScope`, `PrefixScope`, `TypeParameterScope`,
// `InstanceScope`), on element stores built by hand.

use std::rc::Rc;

use analyzer::src::dart::element::element::{
    DirectiveUri, ElementId, ElementKind, ElementStore, FragmentFlag, FragmentImpl, FragmentKind, LibraryElementImpl,
    LibraryFragmentImpl, LibraryId, LibraryImportImpl, PrefixFragmentImpl, UnitId,
};
use analyzer::src::dart::element::scope::{ScopeElement, ScopeFeatures, ScopeId, Scopes};

const FEATURES: ScopeFeatures = ScopeFeatures {
    wildcard_variables: true,
    records: true,
};

fn library(store: &mut ElementStore, uri: &str) -> (LibraryId, UnitId) {
    let id = store.libraries.len() as LibraryId;
    store.libraries.push(LibraryElementImpl::new(Rc::from(uri), Rc::from(""), -1, 0));
    let unit = store.units.len() as UnitId;
    store.units.push(LibraryFragmentImpl::new(id, Rc::from(uri)));
    store.libraries[id as usize].fragments.push(unit);
    (id, unit)
}

fn class(store: &mut ElementStore, library: LibraryId, name: &str) -> ElementId {
    let fragment = store.add_fragment(FragmentImpl::new(FragmentKind::Class, Some(Rc::from(name))));
    let e = store.add_element(ElementKind::CLASS, fragment, library);
    store.libraries[library as usize].classes.push(e);
    store.libraries[library as usize].export_namespace.push((Rc::from(name), e));
    e
}

fn import(store: &mut ElementStore, unit: UnitId, imported: LibraryId, prefix: Option<&str>, deferred: bool) {
    store.units[unit as usize].library_imports.push(LibraryImportImpl {
        is_synthetic: false,
        combinators: Vec::new(),
        import_keyword_offset: 0,
        prefix: prefix.map(|p| PrefixFragmentImpl {
            name: Some(Rc::from(p)),
            name_offset: None,
            offset: 0,
            is_deferred: deferred,
        }),
        uri: DirectiveUri::WithLibrary {
            relative_uri_string: Rc::from(""),
            library: imported,
        },
    });
}

fn getter(scopes: &Scopes, store: &ElementStore, scope: ScopeId, name: &str) -> Option<ScopeElement> {
    scopes.lookup(store, scope, name).getter
}

#[test]
fn library_declarations_shadow_imports() {
    let mut store = ElementStore::new();
    let (a, _) = library(&mut store, "package:p/a.dart");
    let a_x = class(&mut store, a, "X");
    let (main, unit) = library(&mut store, "package:p/main.dart");
    let own_x = class(&mut store, main, "X");
    import(&mut store, unit, a, None, false);
    let mut scopes = Scopes::default();
    scopes.add_library_fragment(&store, unit, None, FEATURES);
    let s = ScopeId::LibraryFragment(unit);
    assert_eq!(getter(&scopes, &store, s, "X"), Some(ScopeElement::Element(own_x)));
    assert_ne!(own_x, a_x);
}

#[test]
fn conflicting_imports_are_multiply_defined_unless_one_is_from_the_sdk() {
    let mut store = ElementStore::new();
    let (core, _) = library(&mut store, "dart:core");
    let sdk_x = class(&mut store, core, "X");
    let (a, _) = library(&mut store, "package:p/a.dart");
    let a_x = class(&mut store, a, "X");
    let a_y = class(&mut store, a, "Y");
    let (b, _) = library(&mut store, "package:p/b.dart");
    let b_y = class(&mut store, b, "Y");
    let (_, unit) = library(&mut store, "package:p/main.dart");
    import(&mut store, unit, core, None, false);
    import(&mut store, unit, a, None, false);
    import(&mut store, unit, b, None, false);
    let mut scopes = Scopes::default();
    scopes.add_library_fragment(&store, unit, None, FEATURES);
    let s = ScopeId::LibraryFragment(unit);
    // A package element wins over an SDK one with the same name.
    assert_eq!(getter(&scopes, &store, s, "X"), Some(ScopeElement::Element(a_x)));
    assert_ne!(a_x, sdk_x);
    assert_eq!(
        getter(&scopes, &store, s, "Y"),
        Some(ScopeElement::MultiplyDefined(Rc::from(vec![a_y, b_y])))
    );
}

#[test]
fn prefixed_imports_are_reached_through_the_prefix() {
    let mut store = ElementStore::new();
    let (a, _) = library(&mut store, "package:p/a.dart");
    let a_x = class(&mut store, a, "X");
    let (_, unit) = library(&mut store, "package:p/main.dart");
    import(&mut store, unit, a, Some("p"), false);
    let mut scopes = Scopes::default();
    scopes.add_library_fragment(&store, unit, None, FEATURES);
    let s = ScopeId::LibraryFragment(unit);
    assert_eq!(getter(&scopes, &store, s, "X"), None);
    let Some(ScopeElement::Prefix(p)) = getter(&scopes, &store, s, "p") else {
        panic!("no prefix");
    };
    assert_eq!(scopes.lookup_prefix(p, "X").getter, Some(ScopeElement::Element(a_x)));
    assert_eq!(scopes.lookup_prefix(p, "loadLibrary").getter, None);
}

#[test]
fn a_deferred_prefix_has_load_library() {
    let mut store = ElementStore::new();
    let (a, _) = library(&mut store, "package:p/a.dart");
    let (_, unit) = library(&mut store, "package:p/main.dart");
    import(&mut store, unit, a, Some("d"), true);
    let mut scopes = Scopes::default();
    scopes.add_library_fragment(&store, unit, None, FEATURES);
    let Some(ScopeElement::Prefix(p)) = getter(&scopes, &store, ScopeId::LibraryFragment(unit), "d") else {
        panic!("no prefix");
    };
    assert_eq!(scopes.lookup_prefix(p, "loadLibrary").getter, Some(ScopeElement::LoadLibrary(a)));
}

#[test]
fn type_parameters_shadow_and_wildcards_are_skipped() {
    let mut store = ElementStore::new();
    let (main, unit) = library(&mut store, "package:p/main.dart");
    let t_class = class(&mut store, main, "T");
    let t = store.add_synthetic_type_parameter(Some(Rc::from("T")), main);
    let wildcard = store.add_synthetic_type_parameter(Some(Rc::from("_")), main);
    let mut scopes = Scopes::default();
    scopes.add_library_fragment(&store, unit, None, FEATURES);
    let s = scopes.type_parameter_scope(&store, ScopeId::LibraryFragment(unit), &[t, wildcard], FEATURES);
    assert_eq!(getter(&scopes, &store, s, "T"), Some(ScopeElement::Element(t)));
    assert_eq!(getter(&scopes, &store, s, "_"), None);
    assert_ne!(t, t_class);
}

#[test]
fn instance_members_hide_outer_names_unless_static() {
    let mut store = ElementStore::new();
    let (main, unit) = library(&mut store, "package:p/main.dart");
    let c = class(&mut store, main, "C");
    let outer_m = class(&mut store, main, "m");
    let outer_s = class(&mut store, main, "s");
    for (name, is_static) in [("m", false), ("s", true)] {
        let fragment = store.add_fragment(FragmentImpl::new(FragmentKind::Method, Some(Rc::from(name))));
        if is_static {
            store.fragment_mut(fragment).flags |= 1u64 << FragmentFlag::executableFragment_isStatic as u8;
        }
        let m = store.add_element(ElementKind::METHOD, fragment, main);
        store.elements[c as usize].members_mut().methods.push(m);
    }
    let mut scopes = Scopes::default();
    scopes.add_library_fragment(&store, unit, None, FEATURES);
    let s = scopes.instance_scope(&store, ScopeId::LibraryFragment(unit), c, true);
    // An instance member ends the lookup with nothing.
    assert_eq!(scopes.lookup(&store, s, "m"), Default::default());
    let static_s = store.elements[c as usize].members().methods[1];
    assert_eq!(getter(&scopes, &store, s, "s"), Some(ScopeElement::Element(static_s)));
    assert_ne!(outer_m, outer_s);
}
