// Not an upstream file: tests of promoted type variables `X & B`
// (`TypeParameterTypeImpl.promotedBound`) in display, equality, nullability,
// subtyping (resources/type-system/subtyping.md), NORM, isBottom and
// isNonNullable.

mod common;

use analyzer::dart::element::nullability_suffix::NullabilitySuffix::{none, question};
use analyzer::src::dart::element::class_hierarchy::ClassHierarchy;
use analyzer::src::dart::element::display_string_builder::display_string;
use analyzer::src::dart::element::normalize::normalize;
use analyzer::src::dart::element::r#type::{type_equals, TypeImpl};
use analyzer::src::dart::element::subtype::TypeSystem;
use analyzer::src::dart::element::type_system::{is_bottom, is_non_nullable};
use common::*;

fn sub(s: &mut Sdk, a: &TypeImpl, b: &TypeImpl) -> bool {
    let mut hierarchy = ClassHierarchy::default();
    TypeSystem::new(&mut s.store, &mut hierarchy).is_subtype_of(a, b)
}

#[test]
fn promoted_type_variables() {
    let mut s = sdk();
    let x = free_type_parameter(&mut s.store, "X", None);
    let k = s.int_();
    let x_int = TypeImpl::promoted_type_parameter(x, none, k.clone());
    assert_eq!(display_string(&s.store, &x_int), "X & int");
    let x_int_q = x_int.with_nullability(&mut s.store, question);
    assert_eq!(display_string(&s.store, &x_int_q), "(X & int)?");
    assert!(!type_equals(&s.store, &x_int, &tp(x, none)));
    assert!(type_equals(&s.store, &x_int, &TypeImpl::promoted_type_parameter(x, none, s.int_())));

    assert!(sub(&mut s, &x_int, &k));
    assert!(sub(&mut s, &x_int, &tp(x, none)));
    let (num_, object_) = (s.num_(), s.object_());
    assert!(sub(&mut s, &x_int, &num_));
    assert!(sub(&mut s, &x_int, &object_));
    assert!(!sub(&mut s, &tp(x, none), &k));
    assert!(!sub(&mut s, &tp(x, none), &x_int));
    assert!(!sub(&mut s, &k, &x_int));

    let x_never = TypeImpl::promoted_type_parameter(x, none, TypeImpl::Never(none));
    assert!(is_bottom(&s.store, &x_never));
    assert!(is_non_nullable(&s.store, &x_int));
    assert!(!is_non_nullable(&s.store, &tp(x, none)));

    let n = normalize(&mut s.store, &x_never);
    assert!(type_equals(&s.store, &n, &TypeImpl::Never(none)));
    let x_top = TypeImpl::promoted_type_parameter(x, none, s.object_q());
    let n = normalize(&mut s.store, &x_top);
    assert!(type_equals(&s.store, &n, &tp(x, none)));
    let n = normalize(&mut s.store, &x_int);
    assert!(type_equals(&s.store, &n, &x_int));
}
