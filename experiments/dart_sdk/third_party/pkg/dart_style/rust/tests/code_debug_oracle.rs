// Oracle for the debug traversals in lib/src/back_end/code.dart.
use dart_style::back_end::code::GroupCode;
mod common;
fn hex(text: &[u16]) -> String {
    text.iter().map(|c| format!("{c:04x}")).collect()
}

#[test]
fn debug_traversals_match_upstream() {
    let expected = common::upstream("code_debug.dart");
    let mut actual = String::new();
    for seed in 0..128 {
        let mut root = GroupCode::new(seed % 140);
        root.newline(true, 99);
        root.write("α😀\n`");
        root.start_selection(-2);
        root.newline(seed % 2 == 0, seed % 5);
        let mut child = GroupCode::new(seed % 9);
        child.write_utf16(&[0xd800]);
        child.end_selection(-1);
        root.group(child);
        root.set_formatting_enabled(false, seed);
        root.write("hidden");
        root.newline(true, 4);
        root.set_formatting_enabled(true, seed + 3);
        actual.push_str(&format!(
            "{seed}:{}:{}\n",
            hex(&root.to_debug_utf16()),
            hex(&root.to_code_tree_utf16())
        ));
    }
    assert_eq!(expected, actual, "debug output differs");
}
