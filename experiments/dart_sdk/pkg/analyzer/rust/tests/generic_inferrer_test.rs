// Not an upstream file: tests of the ports of generic_inferrer.dart
// (`GenericInferrer`), `chooseTypes` and
// `TypeSystemImpl.matchSupertypeConstraints` and
// `instantiateTypeFormalsToBounds`, with the answers inference.md and
// instantiate-to-bound give.

mod common;

use analyzer::dart::element::nullability_suffix::NullabilitySuffix::{none, question};
use analyzer::src::dart::element::class_hierarchy::ClassHierarchy;
use analyzer::src::dart::element::display_string_builder::display_string;
use analyzer::src::dart::element::element::ElementId;
use analyzer::src::dart::element::generic_inferrer::{instantiate_type_formals_to_bounds, match_supertype_constraints};
use analyzer::src::dart::element::r#type::TypeImpl;
use analyzer::src::dart::element::subtype::TypeSystem;
use common::*;

fn matched(s: &mut Sdk, parameters: &[ElementId], src: &[TypeImpl], dest: &[TypeImpl]) -> Option<Vec<String>> {
    let mut hierarchy = ClassHierarchy::default();
    let mut ts = TypeSystem::new(&mut s.store, &mut hierarchy);
    let result = match_supertype_constraints(&mut ts, parameters, src, dest, true)?;
    Some(result.iter().map(|t| display_string(&s.store, t)).collect())
}

fn strings(v: &[&str]) -> Option<Vec<String>> {
    Some(v.iter().map(|x| x.to_string()).collect())
}

#[test]
fn match_supertype_constraints_infers_or_fails() {
    let mut s = sdk();
    let t = free_type_parameter(&mut s.store, "T", None);
    let num_ = s.num_();
    let u = free_type_parameter(&mut s.store, "U", Some(num_));
    let (k, d) = (s.int_(), i(s.double, vec![], none));
    let (lt, lk) = (s.list_of(tp(t, none)), s.list_of(k.clone()));
    assert_eq!(matched(&mut s, &[t], &[lt.clone()], &[lk.clone()]), strings(&["int"]));
    let lkq = s.list_of(i(s.int, vec![], question));
    assert_eq!(matched(&mut s, &[t], &[lt.clone()], &[lkq]), strings(&["int?"]));
    // U is unconstrained: its bound.
    assert_eq!(matched(&mut s, &[t, u], &[lt.clone()], &[lk.clone()]), strings(&["int", "num"]));
    // T would have to be both int and double.
    let pair = class(&mut s.store, s.core, "Pair", None);
    type_parameter(&mut s.store, pair, "A", None);
    type_parameter(&mut s.store, pair, "B", None);
    let ptt = i(pair, vec![tp(t, none), tp(t, none)], none);
    let pkd = i(pair, vec![k.clone(), d.clone()], none);
    assert_eq!(matched(&mut s, &[t], &[ptt.clone()], &[pkd]), None);
    let pkk = i(pair, vec![k.clone(), k.clone()], none);
    assert_eq!(matched(&mut s, &[t], &[ptt], &[pkk]), strings(&["int"]));
    // Two sources share T.
    let ld = s.list_of(d);
    assert_eq!(matched(&mut s, &[t], &[lt.clone(), lt.clone()], &[lk, ld]), None);
}

#[test]
fn instantiate_to_bounds() {
    let mut s = sdk();
    let c = class(&mut s.store, s.core, "C", None);
    type_parameter(&mut s.store, c, "X", None);
    let t = free_type_parameter(&mut s.store, "T", None);
    let u = free_type_parameter(&mut s.store, "U", Some(tp(t, none)));
    let r = free_type_parameter(&mut s.store, "R", None);
    s.store.elements[r as usize].type_ = Some(i(c, vec![tp(r, none)], none));
    let show = |s: &Sdk, v: &[TypeImpl]| v.iter().map(|t| display_string(&s.store, t)).collect::<Vec<_>>();
    // T has no bound: dynamic; U extends T: T's default.
    let (result, error) = instantiate_type_formals_to_bounds(&mut s.store, &[t, u], &[]);
    assert_eq!(show(&s, &result), ["dynamic", "dynamic"]);
    assert!(!error);
    // A known type substitutes into a bound.
    let int_ = s.int_();
    let (result, _) = instantiate_type_formals_to_bounds(&mut s.store, &[t, u], &[(t, int_)]);
    assert_eq!(show(&s, &result), ["int", "int"]);
    // R extends C<R> never grounds: C<dynamic>, with an error.
    let (result, error) = instantiate_type_formals_to_bounds(&mut s.store, &[r], &[]);
    assert_eq!(show(&s, &result), ["C<dynamic>"]);
    assert!(error);
}
