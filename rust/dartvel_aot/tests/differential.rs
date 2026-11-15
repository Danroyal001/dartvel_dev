// Ours (not a ported file): every benchmark program, compiled by
// dartvel_aot in every tree-shaking mode, must print exactly what the stock
// Dart SDK prints, byte for byte, and exit 0.
//
// programs/<name>.expected is `dart run programs/<name>.dart`'s stdout.
// When a Dart SDK is on PATH the test also re-runs the stock SDK and checks
// that the recorded output is still what it prints, so a stale recording
// cannot hide a difference.

mod common;

use common::*;
use dartvel_aot::Mode;

#[test]
fn recorded_outputs_are_the_stock_sdks() {
    let Some(dart) = dart() else {
        eprintln!("no Dart SDK on PATH: checked against the recorded outputs only");
        return;
    };
    for name in programs() {
        let path = programs_dir().join(format!("{name}.dart"));
        let out = std::process::Command::new(&dart)
            .arg("run")
            .arg(&path)
            .output()
            .unwrap();
        assert!(out.status.success(), "stock dart failed on {name}");
        let expected = std::fs::read(programs_dir().join(format!("{name}.expected"))).unwrap();
        assert_eq!(
            String::from_utf8_lossy(&out.stdout),
            String::from_utf8_lossy(&expected),
            "{name}.expected is stale"
        );
    }
}

fn check(mode: Mode) {
    let dir = scratch(&format!("differential-{}", mode.name()));
    let names = programs();
    assert!(names.len() >= 5, "the benchmark programs are missing");
    for name in names {
        let (exe, _) = build(&name, mode, &dir);
        let (stdout, code) = run(&exe);
        let expected = std::fs::read(programs_dir().join(format!("{name}.expected"))).unwrap();
        assert_eq!(
            String::from_utf8_lossy(&stdout),
            String::from_utf8_lossy(&expected),
            "{name} ({}) prints something else than the stock Dart SDK",
            mode.name()
        );
        assert_eq!(stdout, expected, "{name} ({}): bytes differ", mode.name());
        assert_eq!(code, 0, "{name} ({}) exited {code}", mode.name());
    }
    std::fs::remove_dir_all(dir).ok();
}

#[test]
fn identical_to_stock_dart_without_tree_shaking() {
    check(Mode::None);
}

#[test]
fn identical_to_stock_dart_with_call_graph_shaking() {
    check(Mode::Calls);
}

#[test]
fn identical_to_stock_dart_with_type_shaking() {
    check(Mode::Types);
}
