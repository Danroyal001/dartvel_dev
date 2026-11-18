// Focused behavior tests for lib/src/piece/piece.dart's State and Shape.
use dart_style::src::piece::piece::{Shape, State};

#[test]
fn comparison_uses_value_but_equality_uses_identity() {
    let first = State::new(1, 20);
    let second = State::new(1, -5);
    assert_ne!(first, second);
    assert_eq!(first.compare_to(&second), 0);
    assert_eq!(first, first.clone());
    assert_eq!(State::new(-1, 900).compare_to(&first), -1);
    assert_eq!(
        State::new(i64::MAX, 0).compare_to(&State::new(i64::MIN, 0)),
        1
    );
}

#[test]
fn constant_states_are_canonical_by_value_and_cost() {
    assert_eq!(State::canonical(1, 1), State::canonical(1, 1));
    assert_ne!(State::canonical(1, 1), State::canonical(1, 2));
    assert_ne!(State::canonical(1, 1), State::new(1, 1));
}

#[test]
fn inline_is_the_identity_for_merging() {
    for &shape in Shape::ALL {
        assert_eq!(Shape::Inline.merge(shape), shape);
        assert_eq!(shape.merge(Shape::Inline), shape);
    }
}

#[test]
fn merging_multiple_multiline_shapes_loses_their_specific_shape() {
    for &a in &Shape::ALL[1..] {
        for &b in &Shape::ALL[1..] {
            assert_eq!(a.merge(b), Shape::Other);
        }
    }
}
