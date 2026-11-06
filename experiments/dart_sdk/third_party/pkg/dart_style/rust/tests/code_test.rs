// Focused safety/edge cases for the port of lib/src/back_end/code.dart.
use dart_style::back_end::code::GroupCode;
use std::sync::Arc;

#[test]
fn raw_dart_strings_preserve_unpaired_surrogates() {
    let mut group = GroupCode::new(0);
    group.write_utf16(&[0xd800, 0x61, 0xdc00]);
    assert_eq!(
        group.build_utf16(&[], true, None, &[10]),
        (vec![0xd800, 0x61, 0xdc00, 10], None)
    );
}

#[test]
fn selection_offsets_count_utf16_units() {
    let mut group = GroupCode::new(0);
    group.write("😀");
    group.start_selection(0);
    group.write("x");
    group.end_selection(0);
    assert_eq!(
        group.build("😀x", false, Some((2, 1)), "\n"),
        ("😀x".into(), Some((2, 1)))
    );
}

#[test]
fn unvisited_selection_is_placed_after_final_newline() {
    let mut group = GroupCode::new(0);
    group.write("x");
    assert_eq!(
        group.build("abc", true, Some((1, 1)), "\n"),
        ("x\n".into(), Some((2, 0)))
    );
}

#[test]
fn cached_group_can_be_reused_without_copying_its_tree() {
    let mut child = GroupCode::new(2);
    child.write("x");
    let child = Arc::new(child);
    let mut group = GroupCode::new(0);
    group.shared_group(child.clone());
    group.newline(false, 99);
    group.shared_group(child);
    assert_eq!(group.build("", false, None, "\n").0, "  x\n  x");
}

#[test]
fn disabled_region_can_copy_half_of_a_surrogate_pair() {
    let mut group = GroupCode::new(0);
    group.set_formatting_enabled(false, 1);
    group.write("discard");
    assert_eq!(
        group.build_utf16(&[0xd83d, 0xde00], true, None, &[10]).0,
        vec![0xde00]
    );
}

#[test]
fn enabling_without_disabling_has_no_effect() {
    let mut group = GroupCode::new(3);
    group.set_formatting_enabled(true, 200);
    group.write("x");
    assert_eq!(group.build("", false, None, "\n").0, "   x");
}

#[test]
fn unclosed_disabled_region_suppresses_final_newline() {
    let mut group = GroupCode::new(0);
    group.write("before");
    group.set_formatting_enabled(false, 2);
    group.set_formatting_enabled(false, 5);
    group.write("discard");
    assert_eq!(
        group.build("01234567", true, None, "\r\n").0,
        "before234567"
    );
}
