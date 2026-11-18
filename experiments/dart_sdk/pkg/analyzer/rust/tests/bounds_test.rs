// Not an upstream file: tests of the ports of least_upper_bound.dart (UP)
// and greatest_lower_bound.dart (DOWN), with the answers
// resources/type-system/upper-lower-bounds.md gives.

mod common;

use analyzer::dart::element::nullability_suffix::NullabilitySuffix::{none, question};
use analyzer::src::dart::element::class_hierarchy::ClassHierarchy;
use analyzer::src::dart::element::display_string_builder::display_string;
use analyzer::src::dart::element::r#type::TypeImpl;
use analyzer::src::dart::element::subtype::TypeSystem;
use analyzer::src::generated::utilities_dart::ParameterKind::{NAMED, REQUIRED};
use common::*;

fn up(s: &mut Sdk, a: &TypeImpl, b: &TypeImpl) -> String {
    let mut hierarchy = ClassHierarchy::default();
    let t = TypeSystem::new(&mut s.store, &mut hierarchy).least_upper_bound(a, b);
    display_string(&s.store, &t)
}

fn down(s: &mut Sdk, a: &TypeImpl, b: &TypeImpl) -> String {
    let mut hierarchy = ClassHierarchy::default();
    let t = TypeSystem::new(&mut s.store, &mut hierarchy).greatest_lower_bound(a, b);
    display_string(&s.store, &t)
}

#[test]
fn upper_bounds() {
    let mut s = sdk();
    let (k, n) = (s.int_(), s.num_());
    let d = i(s.double, vec![], none);
    let str_ = i(s.string, vec![], none);
    let null = i(s.null, vec![], none);
    assert_eq!(up(&mut s, &k, &n), "num");
    assert_eq!(up(&mut s, &k, &d), "num");
    assert_eq!(up(&mut s, &k, &str_), "Object");
    assert_eq!(up(&mut s, &k, &null), "int?");
    assert_eq!(up(&mut s, &TypeImpl::Unknown, &k), "int");
    assert_eq!(up(&mut s, &k, &TypeImpl::Dynamic), "dynamic");
    assert_eq!(up(&mut s, &TypeImpl::Never(none), &k), "int");
    let (oo, kq) = (s.object_(), i(s.int, vec![], question));
    assert_eq!(up(&mut s, &oo, &kq), "Object?");
    let dq = i(s.double, vec![], question);
    assert_eq!(up(&mut s, &k, &dq), "num?");
    let (lk, ld) = (s.list_of(k.clone()), s.list_of(d.clone()));
    assert_eq!(up(&mut s, &lk, &ld), "List<num>");
    let fo_int = i(s.future_or, vec![k.clone()], none);
    assert_eq!(up(&mut s, &fo_int, &d), "FutureOr<num>");
    // Parameters meet, returns join; an optional named one is dropped.
    let f = function(vec![(n.clone(), REQUIRED, None), (k.clone(), NAMED, Some("a"))], k.clone());
    let g = function(vec![(k.clone(), REQUIRED, None)], d.clone());
    assert_eq!(up(&mut s, &f, &g), "num Function(int)");
    let func = i(s.function, vec![], none);
    assert_eq!(up(&mut s, &f, &func), "Function");
    assert_eq!(up(&mut s, &f, &k), "Object");
    // X & int with num: UP(int, num).
    let x = free_type_parameter(&mut s.store, "X", None);
    let x_int = TypeImpl::promoted_type_parameter(x, none, k.clone());
    assert_eq!(up(&mut s, &x_int, &n), "num");
    assert_eq!(up(&mut s, &x_int, &tp(x, none)), "X");
}

#[test]
fn lower_bounds() {
    let mut s = sdk();
    let (k, n) = (s.int_(), s.num_());
    let d = i(s.double, vec![], none);
    let str_ = i(s.string, vec![], none);
    let null = i(s.null, vec![], none);
    assert_eq!(down(&mut s, &k, &n), "int");
    assert_eq!(down(&mut s, &k, &str_), "Never");
    assert_eq!(down(&mut s, &TypeImpl::Unknown, &k), "int");
    assert_eq!(down(&mut s, &k, &TypeImpl::Dynamic), "int");
    let (kq, nq) = (i(s.int, vec![], question), i(s.num, vec![], question));
    assert_eq!(down(&mut s, &kq, &nq), "int?");
    assert_eq!(down(&mut s, &kq, &n), "int");
    assert_eq!(down(&mut s, &null, &kq), "Null");
    assert_eq!(down(&mut s, &null, &k), "Never");
    let oo = s.object_();
    assert_eq!(down(&mut s, &oo, &kq), "int");
    let x = free_type_parameter(&mut s.store, "X", None);
    assert_eq!(down(&mut s, &oo, &tp(x, none)), "X & Object");
    let (fo_int, fut_num) = (i(s.future_or, vec![k.clone()], none), i(s.future, vec![n.clone()], none));
    assert_eq!(down(&mut s, &fo_int, &fut_num), "Future<int>");
    assert_eq!(down(&mut s, &fo_int, &d), "Never");
    // Parameters join, returns meet.
    let f = function(vec![(k.clone(), REQUIRED, None)], n.clone());
    let g = function(vec![(d.clone(), REQUIRED, None)], k.clone());
    assert_eq!(down(&mut s, &f, &g), "int Function(num)");
}
