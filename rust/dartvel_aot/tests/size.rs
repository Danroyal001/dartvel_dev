// Ours (not a ported file): the tree shaker's contract. A program pays
// only for what it can run: hello world lands in the tens of KiB, and code,
// classes and metadata no reachable code can observe are not emitted.

mod common;

use common::*;
use dartvel_aot::Mode;

/// The size dartc's author was getting back to: 24 KiB. The stock
/// `dart compile exe` hello world is 6.2 MiB.
const HELLO_LIMIT: u64 = 24 * 1024;

fn size(path: &std::path::Path) -> u64 {
    std::fs::metadata(path).unwrap().len()
}

fn kept(report: &str, kind: &str, name: &str) -> bool {
    report.lines().any(|l| l == format!("{kind} {name}"))
}

#[test]
fn hello_world_is_at_most_24_kib() {
    let dir = scratch("size-hello");
    let (exe, _) = build("hello", Mode::Types, &dir);
    let bytes = size(&exe);
    assert!(bytes <= HELLO_LIMIT, "hello world is {bytes} bytes, over {HELLO_LIMIT}");
    assert_eq!(run(&exe).0, b"Hello, World!\n");
    std::fs::remove_dir_all(dir).ok();
}

/// Hello world may cost at most this much more than a C program whose
/// `main` does nothing, built with the same compiler and flags: the bytes
/// that are ours, not the C library's or the ELF format's.
const HELLO_OVER_EMPTY_C: u64 = 2 * 1024;

#[test]
fn hello_world_costs_at_most_2_kib_over_an_empty_c_program() {
    let dir = scratch("size-empty");
    let empty = dir.join("empty");
    dartvel_aot::build_executable("int main(void) { return 0; }\n", &empty).unwrap();
    let (exe, _) = build("hello", Mode::Types, &dir);
    let (empty, hello) = (size(&empty), size(&exe));
    assert!(
        hello <= empty + HELLO_OVER_EMPTY_C,
        "hello world is {hello} bytes, {} over an empty C program ({empty})",
        hello - empty.min(hello)
    );
    std::fs::remove_dir_all(dir).ok();
}

#[test]
fn shaking_by_types_is_never_larger_and_smaller_overall() {
    let dir = scratch("size-modes");
    let (mut total_none, mut total_types) = (0, 0);
    for name in programs() {
        let (none, _) = build(&name, Mode::None, &dir);
        let (calls, _) = build(&name, Mode::Calls, &dir);
        let (types, _) = build(&name, Mode::Types, &dir);
        let (none, calls, types) = (size(&none), size(&calls), size(&types));
        assert!(types <= none, "{name}: types {types} is larger than none {none}");
        assert!(types <= calls, "{name}: types {types} is larger than calls {calls}");
        total_none += none;
        total_types += types;
    }
    assert!(total_types < total_none, "shaking saved nothing: {total_types} against {total_none}");
    std::fs::remove_dir_all(dir).ok();
}

#[test]
fn hello_world_keeps_no_json_no_maps_and_no_class_names() {
    let dir = scratch("size-report");
    let (_, compiled) = build("hello", Mode::Types, &dir);
    let report = compiled.report();
    for function in ["jsonEncode", "jsonDecode", "_JsonParser.parseValue", "int.parse", "Map.toString", "List.join"] {
        assert!(!kept(&report, "function", function), "hello world keeps {function}:\n{report}");
    }
    for class in ["Map", "List", "_JsonParser", "StringBuffer"] {
        assert!(!kept(&report, "class", class), "hello world keeps class {class}:\n{report}");
    }
    assert!(report.contains("class-names dropped"), "hello world keeps class names:\n{report}");
    assert!(!compiled.c_source.contains("dv_names"), "the C still has a class-name table");
    assert!(kept(&report, "function", "print"));
    std::fs::remove_dir_all(dir).ok();
}

#[test]
fn a_class_never_instantiated_keeps_none_of_its_members() {
    let dir = scratch("size-unused");
    let (_, compiled) = build("shapes", Mode::Types, &dir);
    let report = compiled.report();
    assert!(!kept(&report, "class", "Unused"), "{report}");
    assert!(!kept(&report, "function", "Unused.area"), "{report}");
    assert!(!kept(&report, "function", "Unused.name"), "{report}");
    // Instantiated subclasses keep their overrides, the inherited method
    // they all use, and the toString override interpolation reaches.
    for function in ["Rect.area", "Square.name", "Triangle.area", "Shape.describe", "Triangle.toString"] {
        assert!(kept(&report, "function", function), "{function} was dropped:\n{report}");
    }
    // `print(Point(1, 2))` reaches the default toString, so names stay,
    // but only for classes that exist at run time.
    assert!(report.contains("class-names kept"), "{report}");
    assert!(!compiled.c_source.contains("\"Unused\""), "a name for a class never instantiated was emitted");
    // Calls-only shaking keeps Unused, since it assumes every class exists.
    let (_, calls) = build("shapes", Mode::Calls, &dir);
    assert!(kept(&calls.report(), "function", "Unused.area"));
    std::fs::remove_dir_all(dir).ok();
}
