// Oracle for lib/src/back_end/code.dart; compares real upstream code with Rust.
use dart_style::back_end::code::GroupCode;
mod common;

#[test]
fn generated_code_matches_upstream() {
    let expected = common::upstream("code.dart");
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
    let mut relative = GroupCode::new(0);
    relative.write("abc");
    relative.start_selection(-2);
    relative.write("d");
    relative.end_selection(-1);
    let (text, selection) = relative.build("abcd", false, Some((1, 2)), "\n");
    let (start, length) = selection.unwrap();
    actual.push_str(&format!("relative:{text}:{start}:{length}\n"));
    let mut disabled = GroupCode::new(0);
    disabled.write("prefix");
    disabled.set_formatting_enabled(false, 5);
    disabled.start_selection(0);
    disabled.end_selection(0);
    let (text, selection) = disabled.build("0123456789", false, Some((3, 1)), "\n");
    let (start, length) = selection.unwrap();
    actual.push_str(&format!("disabled-relative:{text}:{start}:{length}\n"));
    assert_eq!(expected, actual, "upstream/Rust code generation differs");
}
