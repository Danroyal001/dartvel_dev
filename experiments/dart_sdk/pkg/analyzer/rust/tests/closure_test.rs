// Not an upstream file: tests of the ports of least_greatest_closure.dart and
// of `isBottom` and `isNonNullable`, with the answers the closure rules of
// resources/type-system/inference.md give.

mod common;

use analyzer::dart::element::nullability_suffix::NullabilitySuffix::{none, question};
use analyzer::src::dart::element::least_greatest_closure::{greatest_closure, least_closure};
use analyzer::src::dart::element::r#type::{type_equals, TypeImpl};
use analyzer::src::dart::element::type_system::{is_bottom, is_non_nullable};
use analyzer::src::generated::utilities_dart::ParameterKind::REQUIRED;
use common::*;

fn same(s: &Sdk, a: &TypeImpl, b: &TypeImpl) {
    assert!(type_equals(&s.store, a, b), "{a:?} != {b:?}");
}

#[test]
fn closures_replace_by_variance() {
    let mut s = sdk();
    let t = free_type_parameter(&mut s.store, "T", None);
    let function_ = i(s.function, vec![], none);
    // List<T>: greatest List<Object?>, least List<Never>.
    let list_t = s.list_of(tp(t, none));
    let g = greatest_closure(&mut s.store, &list_t, &[t]);
    same(&s, &g, &s.list_of(s.object_q()));
    let l = least_closure(&mut s.store, &list_t, &[t]);
    same(&s, &l, &s.list_of(TypeImpl::Never(none)));
    // T? at the top: Object? and Never?.
    let g = greatest_closure(&mut s.store, &tp(t, question), &[t]);
    same(&s, &g, &s.object_q());
    let l = least_closure(&mut s.store, &tp(t, question), &[t]);
    same(&s, &l, &TypeImpl::Never(question));
    // T Function(T): the parameter flips.
    let f = function(vec![(tp(t, none), REQUIRED, None)], tp(t, none));
    let g = greatest_closure(&mut s.store, &f, &[t]);
    same(&s, &g, &function(vec![(TypeImpl::Never(none), REQUIRED, None)], s.object_q()));
    // A generic function whose bound mentions T becomes Function or Never.
    let u = free_type_parameter(&mut s.store, "U", Some(tp(t, none)));
    let gf = generic_function(vec![u], vec![], tp(u, none));
    let g = greatest_closure(&mut s.store, &gf, &[t]);
    same(&s, &g, &function_);
    let l = least_closure(&mut s.store, &gf, &[t]);
    same(&s, &l, &TypeImpl::Never(none));
    // Nothing to replace: the same type.
    let k = s.int_();
    let g = greatest_closure(&mut s.store, &k, &[t]);
    same(&s, &g, &k);
}

#[test]
fn bottom_and_non_nullable() {
    let mut s = sdk();
    let never_bound = free_type_parameter(&mut s.store, "N", Some(TypeImpl::Never(none)));
    let int_ = s.int_();
    let int_bound = free_type_parameter(&mut s.store, "I", Some(int_));
    let unbounded = free_type_parameter(&mut s.store, "U", None);
    assert!(is_bottom(&s.store, &TypeImpl::Never(none)));
    assert!(!is_bottom(&s.store, &TypeImpl::Never(question)));
    assert!(is_bottom(&s.store, &tp(never_bound, none)));
    assert!(!is_bottom(&s.store, &tp(never_bound, question)));
    assert!(!is_bottom(&s.store, &s.int_()));

    assert!(is_non_nullable(&s.store, &s.int_()));
    assert!(!is_non_nullable(&s.store, &i(s.int, vec![], question)));
    assert!(!is_non_nullable(&s.store, &i(s.null, vec![], none)));
    assert!(!is_non_nullable(&s.store, &TypeImpl::Dynamic));
    assert!(!is_non_nullable(&s.store, &TypeImpl::Unknown));
    assert!(is_non_nullable(&s.store, &tp(int_bound, none)));
    assert!(!is_non_nullable(&s.store, &tp(unbounded, none)));
    let fo_int_q = i(s.future_or, vec![i(s.int, vec![], question)], none);
    assert!(!is_non_nullable(&s.store, &fo_int_q));
    assert!(is_non_nullable(&s.store, &TypeImpl::Never(none)));
}
