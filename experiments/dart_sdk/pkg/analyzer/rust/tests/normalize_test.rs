// Not an upstream file: tests of the port of normalize.dart (NORM), with the
// results the Dart type system's NORM rules give, on stores built by hand.

use std::rc::Rc;

use analyzer::dart::element::nullability_suffix::NullabilitySuffix::{none, question};
use analyzer::src::dart::element::display_string_builder::display_string;
use analyzer::src::dart::element::element::{
    ElementId, ElementKind, ElementStore, FragmentImpl, FragmentKind, LibraryElementImpl, LibraryFragmentImpl, LibraryId,
};
use analyzer::src::dart::element::normalize::normalize;
use analyzer::src::dart::element::r#type::TypeImpl;

fn library(store: &mut ElementStore, uri: &str) -> LibraryId {
    let id = store.libraries.len() as LibraryId;
    store.libraries.push(LibraryElementImpl::new(Rc::from(uri), Rc::from(""), -1, 0));
    store.units.push(LibraryFragmentImpl::new(id, Rc::from(uri)));
    id
}

fn class(store: &mut ElementStore, library: LibraryId, name: &str) -> ElementId {
    let fragment = store.add_fragment(FragmentImpl::new(FragmentKind::Class, Some(Rc::from(name))));
    let e = store.add_element(ElementKind::CLASS, fragment, library);
    store.libraries[library as usize].classes.push(e);
    e
}

struct Sdk {
    store: ElementStore,
    object: ElementId,
    null: ElementId,
    int: ElementId,
    future_or: ElementId,
}

fn sdk() -> Sdk {
    let mut store = ElementStore::new();
    let core = library(&mut store, "dart:core");
    let object = class(&mut store, core, "Object");
    let null = class(&mut store, core, "Null");
    let int = class(&mut store, core, "int");
    let async_ = library(&mut store, "dart:async");
    class(&mut store, async_, "Future");
    let future_or = class(&mut store, async_, "FutureOr");
    Sdk { store, object, null, int, future_or }
}

fn i(element: ElementId, args: Vec<TypeImpl>, s: analyzer::dart::element::nullability_suffix::NullabilitySuffix) -> TypeImpl {
    TypeImpl::interface(element, args, s)
}

fn norm(sdk: &mut Sdk, t: TypeImpl) -> String {
    let n = normalize(&mut sdk.store, &t);
    display_string(&sdk.store, &n)
}

#[test]
fn future_or_rules() {
    let mut s = sdk();
    let (object, int, null, fo) = (s.object, s.int, s.null, s.future_or);
    // NORM(FutureOr<T>) = S when S is a top type or Object.
    assert_eq!(norm(&mut s, i(fo, vec![TypeImpl::Dynamic], none)), "dynamic");
    assert_eq!(norm(&mut s, i(fo, vec![i(object, vec![], none)], none)), "Object");
    assert_eq!(norm(&mut s, i(fo, vec![i(object, vec![], question)], none)), "Object?");
    // ... Future<Never> when S is Never, Future<Null>? when S is Null.
    assert_eq!(norm(&mut s, i(fo, vec![TypeImpl::Never(none)], none)), "Future<Never>");
    assert_eq!(norm(&mut s, i(fo, vec![i(null, vec![], none)], none)), "Future<Null>?");
    // ... FutureOr<S> otherwise.
    assert_eq!(norm(&mut s, i(fo, vec![i(int, vec![], none)], none)), "FutureOr<int>");
}

#[test]
fn nullable_rules() {
    let mut s = sdk();
    let (int, null, fo) = (s.int, s.null, s.future_or);
    // NORM(T?) is Null when S is Never or Null.
    assert_eq!(norm(&mut s, TypeImpl::Never(question)), "Null");
    assert_eq!(norm(&mut s, i(null, vec![], question)), "Null");
    // ... S when S is FutureOr<R> with R nullable.
    assert_eq!(norm(&mut s, i(fo, vec![i(int, vec![], question)], question)), "FutureOr<int?>");
    // ... S? otherwise.
    assert_eq!(norm(&mut s, i(int, vec![], question)), "int?");
    assert_eq!(norm(&mut s, i(fo, vec![i(int, vec![], none)], question)), "FutureOr<int>?");
}

#[test]
fn type_parameter_bounded_by_never_is_never() {
    let mut s = sdk();
    let t = s.store.add_synthetic_type_parameter(Some(Rc::from("T")), 0);
    s.store.elements[t as usize].type_ = Some(TypeImpl::Never(none));
    assert_eq!(norm(&mut s, TypeImpl::type_parameter(t, none)), "Never");
    let u = s.store.add_synthetic_type_parameter(Some(Rc::from("U")), 0);
    let int = s.int;
    s.store.elements[u as usize].type_ = Some(i(int, vec![], none));
    assert_eq!(norm(&mut s, TypeImpl::type_parameter(u, none)), "U");
}
