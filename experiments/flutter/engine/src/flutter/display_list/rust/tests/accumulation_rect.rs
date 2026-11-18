// Port of flutter/display_list/utils/dl_accumulation_rect_unittests.cc.
#![forbid(unsafe_code)]
use display_list::dl_accumulation_rect::AccumulationRect;
use impeller_geometry::{point::Point, rect::Rect};

fn rect(v: [f32; 4]) -> Rect {
    Rect::make_ltrb(v[0], v[1], v[2], v[3])
}
fn check(a: &AccumulationRect, bounds: [f32; 4], empty: bool, overlap: bool) {
    assert_eq!(a.is_empty(), empty);
    assert_eq!(a.is_not_empty(), !empty);
    assert_eq!(a.get_bounds().is_empty(), empty);
    assert_eq!(a.get_bounds(), rect(bounds));
    assert_eq!(a.overlap_detected(), overlap);
}

#[test]
fn constructor() {
    check(&AccumulationRect::default(), [0.0; 4], true, false);
}
#[test]
fn one_point() {
    let mut a = AccumulationRect::default();
    a.accumulate(10.0, 10.0);
    check(&a, [10.0; 4], true, false);
}
#[test]
fn two_points() {
    for (end, empty) in [
        ([10.0, 10.0], true),
        ([20.0, 10.0], true),
        ([10.0, 20.0], true),
        ([20.0, 20.0], false),
    ] {
        for point_overload in [false, true] {
            let mut a = AccumulationRect::default();
            for [x, y] in [[10.0, 10.0], end] {
                if point_overload {
                    a.accumulate_point(Point::new(x, y));
                } else {
                    a.accumulate(x, y);
                }
            }
            check(&a, [10.0, 10.0, end[0], end[1]], empty, false);
        }
    }
}
#[test]
fn three_points() {
    for (points, bounds, empty, overlap) in [
        ([[10.0, 10.0]; 3], [10.0; 4], true, false),
        (
            [[10.0, 10.0], [20.0, 10.0], [15.0, 10.0]],
            [10.0, 10.0, 20.0, 10.0],
            true,
            false,
        ),
        (
            [[10.0, 10.0], [10.0, 20.0], [10.0, 15.0]],
            [10.0, 10.0, 10.0, 20.0],
            true,
            false,
        ),
        (
            [[10.0, 10.0], [20.0, 20.0], [25.0, 15.0]],
            [10.0, 10.0, 25.0, 20.0],
            false,
            false,
        ),
        (
            [[10.0, 10.0], [20.0, 20.0], [15.0, 15.0]],
            [10.0, 10.0, 20.0, 20.0],
            false,
            true,
        ),
    ] {
        for point_overload in [false, true] {
            let mut a = AccumulationRect::default();
            for [x, y] in points {
                if point_overload {
                    a.accumulate_point(Point::new(x, y));
                } else {
                    a.accumulate(x, y);
                }
            }
            check(&a, bounds, empty, overlap);
        }
    }
}
#[test]
fn empty_rect() {
    for (r, empty) in [
        ([10.0; 4], true),
        ([10.0, 10.0, 20.0, 10.0], true),
        ([10.0, 10.0, 10.0, 20.0], true),
        ([10.0, 10.0, 20.0, 20.0], false),
    ] {
        let bounds = if empty { [0.0; 4] } else { r };
        let mut a = AccumulationRect::default();
        a.accumulate_rect(rect(r));
        check(&a, bounds, empty, false);
        let mut content = AccumulationRect::default();
        content.accumulate(r[0], r[1]);
        content.accumulate(r[2], r[3]);
        assert_eq!(content.is_empty(), empty);
        assert!(!content.overlap_detected());
        if !empty {
            assert_eq!(content.get_bounds(), rect(bounds));
        }
        let mut a = AccumulationRect::default();
        a.accumulate_accumulator(&content);
        check(&a, bounds, empty, false);
    }
}
#[test]
fn two_rects() {
    for (first, second, bounds, empty, overlap) in [
        ([10.0; 4], [20.0; 4], [0.0; 4], true, false),
        (
            [10.0, 10.0, 20.0, 10.0],
            [10.0, 10.0, 10.0, 20.0],
            [0.0; 4],
            true,
            false,
        ),
        (
            [10.0; 4],
            [15.0, 15.0, 20.0, 20.0],
            [15.0, 15.0, 20.0, 20.0],
            false,
            false,
        ),
        (
            [10.0, 10.0, 15.0, 15.0],
            [20.0; 4],
            [10.0, 10.0, 15.0, 15.0],
            false,
            false,
        ),
        (
            [10.0, 10.0, 15.0, 15.0],
            [15.0, 15.0, 20.0, 20.0],
            [10.0, 10.0, 20.0, 20.0],
            false,
            false,
        ),
        (
            [10.0, 10.0, 15.0, 15.0],
            [16.0, 16.0, 20.0, 20.0],
            [10.0, 10.0, 20.0, 20.0],
            false,
            false,
        ),
        (
            [10.0, 10.0, 16.0, 16.0],
            [15.0, 15.0, 20.0, 20.0],
            [10.0, 10.0, 20.0, 20.0],
            false,
            true,
        ),
    ] {
        for merge in [false, true] {
            let mut a = AccumulationRect::default();
            for r in [first, second] {
                if merge {
                    let mut content = AccumulationRect::default();
                    content.accumulate(r[0], r[1]);
                    content.accumulate(r[2], r[3]);
                    a.accumulate_accumulator(&content);
                } else {
                    a.accumulate_rect(rect(r));
                }
            }
            check(&a, bounds, empty, overlap);
        }
    }
}

// Added regression: the upper edges are exclusive, non-finite points are ignored,
// and merging does not inherit the source accumulator's overlap flag.
#[test]
fn edge_nonfinite_reset_and_merge() {
    let mut a = AccumulationRect::default();
    a.accumulate_rect(rect([0.0, 0.0, 10.0, 10.0]));
    a.accumulate(10.0, 5.0);
    a.accumulate(f32::INFINITY, 3.0);
    a.accumulate(3.0, f32::NAN);
    check(&a, [0.0, 0.0, 10.0, 10.0], false, false);
    a.accumulate(0.0, 5.0);
    assert!(a.overlap_detected());
    let mut b = AccumulationRect::default();
    b.accumulate_accumulator(&a);
    check(&b, [0.0, 0.0, 10.0, 10.0], false, false);
    b.record_overlapping_bounds();
    assert!(b.overlap_detected());
    b.reset();
    check(&b, [0.0; 4], true, false);
}
