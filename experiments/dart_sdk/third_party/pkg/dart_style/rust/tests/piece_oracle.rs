// Oracle for State and Shape in lib/src/piece/piece.dart.
use dart_style::src::piece::piece::{Shape, State};
mod common;
#[test]
fn states_and_shapes_match_upstream() {
    let expected = common::upstream("piece.dart");
    let mut states = vec![
        State::canonical(0, 0),
        State::canonical(255, 1),
        State::new(0, 0),
        State::new(255, 1),
        State::canonical(1, 1),
        State::canonical(1, 1),
        State::new(1, 1),
        State::new(1, 1),
        State::canonical(1, 4),
        State::canonical(1, 4),
        State::canonical(0, 0),
        State::canonical(255, 1),
    ];
    for n in [-500, -1, 0, 1, 254, 255, 256, 1000000] {
        states.push(State::new(n, -n));
    }
    let mut actual = String::new();
    for (i, a) in states.iter().enumerate() {
        actual.push_str(&format!("state:{i}:{a}:{}\n", a.cost()));
        for (j, b) in states.iter().enumerate() {
            actual.push_str(&format!("pair:{i}:{j}:{}:{}\n", a.compare_to(b), a == b));
        }
    }
    for &a in Shape::ALL {
        for &b in Shape::ALL {
            actual.push_str(&format!(
                "merge:{}:{}:{}\n",
                a.name(),
                b.name(),
                a.merge(b).name()
            ));
        }
    }
    for shapes in [
        Shape::ALL,
        Shape::ONLY_BLOCK,
        Shape::ONLY_INLINE,
        Shape::INLINE_OR_BLOCK,
        Shape::any_if(false),
        Shape::any_if(true),
    ] {
        actual.push_str(&format!(
            "set:{}\n",
            shapes
                .iter()
                .map(|s| s.name())
                .collect::<Vec<_>>()
                .join(",")
        ));
    }
    assert_eq!(expected, actual);
}
