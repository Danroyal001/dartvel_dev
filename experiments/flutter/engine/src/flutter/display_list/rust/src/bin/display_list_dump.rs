// Not an upstream file: differential driver for display_list foundation.
#![forbid(unsafe_code)]
use display_list::{
    dl_accumulation_rect::AccumulationRect, dl_sampling_options::*, dl_tile_mode::*, dl_types::*,
};
use impeller_geometry::rect::Rect;
use std::io::{self, BufRead, Write};

fn scalar(words: &mut std::str::SplitWhitespace<'_>) -> f32 {
    f32::from_bits(
        words
            .next()
            .expect("missing scalar")
            .parse()
            .expect("invalid bits"),
    )
}
fn rect(words: &mut std::str::SplitWhitespace<'_>) -> Rect {
    Rect::make_ltrb(scalar(words), scalar(words), scalar(words), scalar(words))
}
fn main() {
    let stdin = io::stdin();
    let mut out = io::BufWriter::new(io::stdout().lock());
    let mut acc = AccumulationRect::default();
    for line in stdin.lock().lines() {
        let line = line.unwrap();
        let mut words = line.split_whitespace();
        match words.next() {
            Some("reset") => acc.reset(),
            Some("point") => acc.accumulate(scalar(&mut words), scalar(&mut words)),
            Some("rect") => acc.accumulate_rect(rect(&mut words)),
            Some("merge") => {
                let n: usize = words.next().unwrap().parse().unwrap();
                let mut other = AccumulationRect::default();
                for _ in 0..n {
                    other.accumulate_rect(rect(&mut words));
                }
                acc.accumulate_accumulator(&other);
            }
            Some("overlap") => acc.record_overlapping_bounds(),
            Some("enums") => {
                writeln!(
                    out,
                    "enums {} {} {} {} {} {} {} {} {} {} {} {}",
                    size_of::<DlClipOp>(),
                    size_of::<DlPointMode>(),
                    size_of::<DlSrcRectConstraint>(),
                    size_of::<DlFilterMode>(),
                    size_of::<DlImageSampling>(),
                    size_of::<DlTileMode>(),
                    DlClipOp::Intersect as i32,
                    DlPointMode::Polygon as i32,
                    DlSrcRectConstraint::Fast as i32,
                    DlFilterMode::kLast as i32,
                    DlImageSampling::Cubic as i32,
                    DlTileMode::Decal as i32
                )
                .unwrap();
                continue;
            }
            None => continue,
            _ => panic!("unknown operation"),
        }
        assert!(words.next().is_none(), "trailing input");
        let r = acc.get_bounds();
        writeln!(
            out,
            "{:08x} {:08x} {:08x} {:08x} {} {} {}",
            r.get_left().to_bits(),
            r.get_top().to_bits(),
            r.get_right().to_bits(),
            r.get_bottom().to_bits(),
            acc.is_empty() as u8,
            acc.is_not_empty() as u8,
            acc.overlap_detected() as u8
        )
        .unwrap();
    }
}
