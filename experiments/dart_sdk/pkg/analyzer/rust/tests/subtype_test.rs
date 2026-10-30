// Not an upstream file: tests of the port of subtype.dart, with the answers
// the Dart subtyping rules (resources/type-system/subtyping.md) give, on
// stores built by hand: Object, Null, num, int, Function in dart:core,
// Future and FutureOr in dart:async, and a generic List<E>.

use std::rc::Rc;

use analyzer::dart::element::nullability_suffix::NullabilitySuffix::{self, none, question};
use analyzer::src::dart::element::class_hierarchy::ClassHierarchy;
use analyzer::src::dart::element::element::{
    ElementId, ElementKind, ElementStore, FragmentImpl, FragmentKind, LibraryElementImpl, LibraryFragmentImpl, LibraryId,
};
use analyzer::src::dart::element::r#type::{FormalParameter, FunctionTypeImpl, TypeImpl};
use analyzer::src::dart::element::subtype::TypeSystem;
use analyzer::src::generated::utilities_dart::ParameterKind;

struct Sdk {
    store: ElementStore,
    object: ElementId,
    null: ElementId,
    num: ElementId,
    int: ElementId,
    list: ElementId,
    list_e: ElementId,
    future: ElementId,
    future_or: ElementId,
    function: ElementId,
}

fn library(store: &mut ElementStore, uri: &str) -> LibraryId {
    let id = store.libraries.len() as LibraryId;
    store.libraries.push(LibraryElementImpl::new(Rc::from(uri), Rc::from(""), -1, 0));
    store.units.push(LibraryFragmentImpl::new(id, Rc::from(uri)));
    id
}

fn class(store: &mut ElementStore, library: LibraryId, name: &str, supertype: Option<TypeImpl>) -> ElementId {
    let fragment = store.add_fragment(FragmentImpl::new(FragmentKind::Class, Some(Rc::from(name))));
    let e = store.add_element(ElementKind::CLASS, fragment, library);
    store.libraries[library as usize].classes.push(e);
    store.elements[e as usize].type_ = supertype;
    e
}

fn i(element: ElementId, args: Vec<TypeImpl>, s: NullabilitySuffix) -> TypeImpl {
    TypeImpl::interface(element, args, s)
}

fn sdk() -> Sdk {
    let mut store = ElementStore::new();
    let core = library(&mut store, "dart:core");
    let object = class(&mut store, core, "Object", None);
    let o = i(object, vec![], none);
    let null = class(&mut store, core, "Null", Some(o.clone()));
    let num = class(&mut store, core, "num", Some(o.clone()));
    let int = class(&mut store, core, "int", Some(i(num, vec![], none)));
    let function = class(&mut store, core, "Function", Some(o.clone()));
    let list = class(&mut store, core, "List", Some(o.clone()));
    let e_fragment = store.add_fragment(FragmentImpl::new(FragmentKind::TypeParameter, Some(Rc::from("E"))));
    let list_e = store.add_element(ElementKind::TYPE_PARAMETER, e_fragment, core);
    let list_first = store.element(list).first_fragment;
    store.fragment_mut(list_first).type_parameters.push(e_fragment);
    let async_ = library(&mut store, "dart:async");
    let future = class(&mut store, async_, "Future", Some(o.clone()));
    let future_or = class(&mut store, async_, "FutureOr", Some(o));
    Sdk { store, object, null, num, int, list, list_e, future, future_or, function }
}

fn sub(s: &mut Sdk, a: &TypeImpl, b: &TypeImpl) -> bool {
    let mut hierarchy = ClassHierarchy::default();
    TypeSystem::new(&mut s.store, &mut hierarchy).is_subtype_of(a, b)
}

#[test]
fn interfaces_and_nullability() {
    let mut s = sdk();
    let (object, null, num, int) = (s.object, s.null, s.num, s.int);
    assert!(sub(&mut s, &i(int, vec![], none), &i(num, vec![], none)));
    assert!(!sub(&mut s, &i(num, vec![], none), &i(int, vec![], none)));
    assert!(sub(&mut s, &i(int, vec![], none), &i(num, vec![], question)));
    assert!(!sub(&mut s, &i(int, vec![], question), &i(num, vec![], none)));
    assert!(sub(&mut s, &i(null, vec![], none), &i(int, vec![], question)));
    assert!(!sub(&mut s, &i(null, vec![], none), &i(int, vec![], none)));
    assert!(sub(&mut s, &i(int, vec![], question), &i(object, vec![], question)));
    assert!(!sub(&mut s, &i(int, vec![], question), &i(object, vec![], none)));
    assert!(sub(&mut s, &TypeImpl::Never(none), &i(int, vec![], none)));
    assert!(sub(&mut s, &TypeImpl::Dynamic, &i(object, vec![], question)));
    assert!(!sub(&mut s, &TypeImpl::Dynamic, &i(object, vec![], none)));
}

#[test]
fn generics_are_covariant() {
    let mut s = sdk();
    let (list, num, int) = (s.list, s.num, s.int);
    let _ = s.list_e;
    assert!(sub(&mut s, &i(list, vec![i(int, vec![], none)], none), &i(list, vec![i(num, vec![], none)], none)));
    assert!(!sub(&mut s, &i(list, vec![i(num, vec![], none)], none), &i(list, vec![i(int, vec![], none)], none)));
}

#[test]
fn future_or() {
    let mut s = sdk();
    let (int, future, fo, null) = (s.int, s.future, s.future_or, s.null);
    let fo_int = i(fo, vec![i(int, vec![], none)], none);
    assert!(sub(&mut s, &i(int, vec![], none), &fo_int));
    assert!(sub(&mut s, &i(future, vec![i(int, vec![], none)], none), &fo_int));
    assert!(!sub(&mut s, &i(null, vec![], none), &fo_int));
    let fo_int_q = i(fo, vec![i(int, vec![], question)], none);
    assert!(sub(&mut s, &i(null, vec![], none), &fo_int_q));
}

fn function(params: Vec<(TypeImpl, ParameterKind, Option<&str>)>, ret: TypeImpl) -> TypeImpl {
    let formal_parameters = params
        .into_iter()
        .map(|(t, kind, name)| FormalParameter { name: name.map(Rc::from), type_: t, kind })
        .collect();
    TypeImpl::Function(Rc::new(FunctionTypeImpl::new(Vec::new(), formal_parameters, ret, none)))
}

#[test]
fn functions_are_contravariant_in_parameters() {
    let mut s = sdk();
    let (num, int, function_class) = (s.num, s.int, s.function);
    let n = i(num, vec![], none);
    let k = i(int, vec![], none);
    // int Function(num) <: num Function(int).
    let f = function(vec![(n.clone(), ParameterKind::REQUIRED, None)], k.clone());
    let g = function(vec![(k.clone(), ParameterKind::REQUIRED, None)], n.clone());
    assert!(sub(&mut s, &f, &g));
    assert!(!sub(&mut s, &g, &f));
    // A function type is a subtype of Function.
    assert!(sub(&mut s, &f, &i(function_class, vec![], none)));
    // An optional named parameter may be left out by the supertype; a
    // required one may not.
    let opt = function(vec![(k.clone(), ParameterKind::NAMED, Some("a"))], k.clone());
    let req = function(vec![(k.clone(), ParameterKind::NAMED_REQUIRED, Some("a"))], k.clone());
    let nothing = function(vec![], k.clone());
    assert!(sub(&mut s, &opt, &nothing));
    assert!(!sub(&mut s, &req, &nothing));
}

#[test]
fn unknown_is_top_and_bottom() {
    // `_` is treated as a top and a bottom type during inference.
    let mut s = sdk();
    let (int, list) = (s.int, s.list);
    let k = i(int, vec![], none);
    assert!(sub(&mut s, &TypeImpl::Unknown, &k));
    assert!(sub(&mut s, &k, &TypeImpl::Unknown));
    assert!(sub(&mut s, &i(list, vec![TypeImpl::Unknown], none), &i(list, vec![k.clone()], none)));
    assert!(analyzer::src::dart::element::type_system::is_top(&s.store, &TypeImpl::Unknown));
    assert!(analyzer::src::dart::element::type_system::is_nullable(&s.store, &TypeImpl::Unknown));
}
