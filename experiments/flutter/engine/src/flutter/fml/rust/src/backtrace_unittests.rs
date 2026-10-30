// Port of flutter/fml/backtrace_unittests.cc.

use super::backtrace::*;

#[test]
fn can_gather_backtrace() {
    if !is_crash_handling_supported() {
        return;
    }
    {
        let trace = backtrace_here(0);
        assert!(!trace.is_empty());
        assert!(trace.contains("Frame 0"));
    }

    {
        let trace = backtrace_here(1);
        assert!(!trace.is_empty());
        assert!(trace.contains("Frame 0"));
    }

    {
        let trace = backtrace_here(2);
        assert!(!trace.is_empty());
        assert!(trace.contains("Frame 0"));
    }
}

// Not upstream's: frames are named from the symbol tables, so this test's
// own function shows up by (mangled) name, and every frame's line has
// upstream's shape.
#[test]
fn frames_are_symbolized() {
    let trace = backtrace_here(0);
    assert!(trace.contains("frames_are_symbolized"), "{trace}");
    for (i, line) in trace.lines().enumerate() {
        let prefix = format!("Frame {i}: 0x");
        assert!(line.starts_with(&prefix), "{line}");
        assert!(line[prefix.len()..].contains(' '), "{line}");
    }
}
