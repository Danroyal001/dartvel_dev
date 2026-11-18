// Not an upstream file: tests of the port of type_constraint_gatherer.dart
// and _fe_analyzer_shared's TypeConstraintGenerator: the subtype match
// rules of resources/type-system/inference.md, read as the merged
// constraint `lower <: T <: upper` each match leaves.

mod common;

use analyzer::dart::element::nullability_suffix::NullabilitySuffix::{none, question};
use analyzer::src::dart::element::class_hierarchy::ClassHierarchy;
use analyzer::src::dart::element::display_string_builder::display_string;
use analyzer::src::dart::element::element::ElementId;
use analyzer::src::dart::element::r#type::TypeImpl;
use analyzer::src::dart::element::subtype::TypeSystem;
use analyzer::src::dart::element::type_constraint_gatherer::TypeConstraintGatherer;
use analyzer::src::generated::utilities_dart::ParameterKind::REQUIRED;
use common::*;

/// Matches `p <: q` for [parameters]; the merged constraints as
/// `lower <: T <: upper`, or `None` when the match fails.
fn gather(s: &mut Sdk, parameters: &[ElementId], p: &TypeImpl, q: &TypeImpl, bounds: bool) -> Option<Vec<String>> {
    let mut hierarchy = ClassHierarchy::default();
    let mut ts = TypeSystem::new(&mut s.store, &mut hierarchy);
    let mut gatherer = TypeConstraintGatherer::new(&mut ts, parameters.to_vec(), bounds);
    if !gatherer.perform_subtype_constraint_generation(p, q, false) {
        return None;
    }
    let constraints = gatherer.compute_constraints();
    Some(
        constraints
            .iter()
            .map(|(_, c)| format!("{} <: T <: {}", display_string(&s.store, &c.lower), display_string(&s.store, &c.upper)))
            .collect(),
    )
}

#[test]
fn subtype_matches() {
    let mut s = sdk();
    let t = free_type_parameter(&mut s.store, "T", None);
    let tt = tp(t, none);
    let (k, n) = (s.int_(), s.num_());
    let str_ = i(s.string, vec![], none);
    let one = |c: &str| Some(vec![c.to_string()]);

    let (lt, lk) = (s.list_of(tt.clone()), s.list_of(k.clone()));
    assert_eq!(gather(&mut s, &[t], &lt, &lk, true), one("_ <: T <: int"));
    assert_eq!(gather(&mut s, &[t], &k, &tt, true), one("int <: T <: _"));
    assert_eq!(gather(&mut s, &[t], &lk, &lt, true), one("int <: T <: _"));
    let (tq, kq) = (tp(t, question), i(s.int, vec![], question));
    assert_eq!(gather(&mut s, &[t], &tq, &kq, true), one("_ <: T <: int"));
    // Parameters are contravariant.
    let f = function(vec![(tt.clone(), REQUIRED, None)], k.clone());
    let g = function(vec![(n.clone(), REQUIRED, None)], k.clone());
    assert_eq!(gather(&mut s, &[t], &f, &g, true), one("num <: T <: _"));
    // int <: FutureOr<T>: Future<T> does not match, so T >: int.
    let fo_t = i(s.future_or, vec![tt.clone()], none);
    assert_eq!(gather(&mut s, &[t], &k, &fo_t, true), one("int <: T <: _"));
    // Future<int> <: FutureOr<T>: the Future match adds constraints, so it wins.
    let fut_k = i(s.future, vec![k.clone()], none);
    assert_eq!(gather(&mut s, &[t], &fut_k, &fo_t, true), one("int <: T <: _"));
    // Through a superclass: B<int> extends List<int>.
    let b = class(&mut s.store, s.core, "B", None);
    let x = type_parameter(&mut s.store, b, "X", None);
    s.store.elements[b as usize].type_ = Some(s.list_of(tp(x, none)));
    let bk = i(b, vec![k.clone()], none);
    assert_eq!(gather(&mut s, &[t], &bk, &lt, true), one("int <: T <: _"));
    // Two constraints merge: LUB of the lowers.
    let d = i(s.double, vec![], none);
    let rec_p = s.list_of(s.list_of(tt.clone()));
    let rec_q = s.list_of(s.list_of(d));
    assert_eq!(gather(&mut s, &[t], &rec_q, &rec_p, true), one("double <: T <: _"));
    // No match.
    assert_eq!(gather(&mut s, &[t], &str_, &lt, true), None);
    // An unconstrained parameter stays `_ <: T <: _`.
    assert_eq!(gather(&mut s, &[t], &k, &n, true), one("_ <: T <: _"));
}

#[test]
fn inference_using_bounds() {
    let mut s = sdk();
    let str_ = i(s.string, vec![], none);
    let t = free_type_parameter(&mut s.store, "T", Some(str_));
    let (k, tt) = (s.int_(), tp(t, none));
    // With the feature, int is not a lower bound of T extends String.
    assert_eq!(gather(&mut s, &[t], &k, &tt, true), None);
    assert_eq!(gather(&mut s, &[t], &k, &tt, false), Some(vec!["int <: T <: _".to_string()]));
}
