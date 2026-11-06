// Oracle for lib/src/back_end/code.dart; compares real upstream code with Rust.
use dart_style::back_end::code::GroupCode;
use std::process::Command;

#[test]
fn generated_code_matches_upstream() {
    let dart = std::env::var("DART").expect("DART must name the Dart 3.13.3 binary");
    let version = Command::new(&dart).arg("--version").output().unwrap();
    let version = format!(
        "{}{}",
        String::from_utf8_lossy(&version.stdout),
        String::from_utf8_lossy(&version.stderr)
    );
    assert!(
        version.contains("Dart SDK version: 3.13.3 "),
        "wrong oracle: {version}"
    );
    let output = Command::new(dart)
        .arg(format!("{}/oracle/code.dart", env!("CARGO_MANIFEST_DIR")))
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let mut actual = String::new();
    for seed in 0..256 {
        let mut root = GroupCode::new(seed % 5);
        root.newline(true, 99);
        root.write("α😀");
        root.start_selection(1);
        root.write("x");
        root.newline(seed % 2 == 0, seed % 140);
        let mut child = GroupCode::new(seed % 7);
        child.write("nested");
        child.end_selection(0);
        root.group(child);
        if seed % 3 == 0 {
            root.set_formatting_enabled(false, 2);
            root.write("discarded");
            root.start_selection(0);
            root.newline(true, 100);
            root.set_formatting_enabled(false, 5);
            if seed % 6 == 0 {
                root.set_formatting_enabled(true, 9);
            }
        }
        root.write("end");
        root.end_selection(0);
        let (text, selection) = root.build(
            "ab😀efghijk",
            seed % 2 == 0,
            Some((4, 3)),
            if seed % 4 == 0 { "\r\n" } else { "\n" },
        );
        let hex: String = text.encode_utf16().map(|c| format!("{c:04x}")).collect();
        let (start, len) = selection.expect("source selection retained");
        actual.push_str(&format!("{seed}:{hex}:{start}:{len}\n"));
    }
    for mode in 0..4 {
        let mut root = GroupCode::new(4);
        root.newline(true, 9);
        if mode > 1 {
            root.write("tail");
        }
        let (text, selection) = root.build("", mode % 2 == 0, None, "\n");
        assert_eq!(selection, None);
        let hex: String = text.encode_utf16().map(|c| format!("{c:04x}")).collect();
        actual.push_str(&format!("empty{mode}:{hex}:null:null\n"));
    }
    assert_eq!(
        String::from_utf8(output.stdout).unwrap(),
        actual,
        "upstream/Rust code generation differs"
    );
}
