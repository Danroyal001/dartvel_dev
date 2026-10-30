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

// Not upstream's: frames are named from the symbol tables, so a function on
// the stack shows up by (mangled) name, and every frame's line has
// upstream's shape. BacktraceHere leaves out its caller's frame (as
// upstream's compiled code does), so the name looked for is the caller's
// caller, and both are kept out of line so that the frames exist in every
// build.
#[inline(never)]
fn calls_backtrace_here() -> String {
    std::hint::black_box(backtrace_here(0))
}

#[inline(never)]
fn named_frame_for_the_backtrace() -> String {
    std::hint::black_box(calls_backtrace_here())
}

#[test]
fn frames_are_symbolized() {
    let trace = named_frame_for_the_backtrace();
    assert!(trace.contains("named_frame_for_the_backtrace"), "{trace}");
    assert!(!trace.contains("calls_backtrace_here"), "{trace}");
    for (i, line) in trace.lines().enumerate() {
        let prefix = format!("Frame {i}: 0x");
        assert!(line.starts_with(&prefix), "{line}");
        assert!(line[prefix.len()..].contains(' '), "{line}");
    }
}
