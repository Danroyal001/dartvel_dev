// Not an upstream file: the port's side of the oracle (see
// oracle/geometry_dump.cc, which this mirrors suite by suite and line by line).
//
//   geometry_dump <suite> <seed> <cases>
//   geometry_dump bench <suite> <rounds>

#![allow(non_snake_case)]

use std::io::Write;

use impeller_geometry::constants::*;
use impeller_geometry::saturated;
use impeller_geometry::scalar::*;

// ---------------------------------------------------------------- rng ------

struct Rng {
    s: u64,
}

impl Rng {
    fn next(&mut self) -> u64 {
        self.s = self.s.wrapping_add(0x9e3779b97f4a7c15);
        let mut z = self.s;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
        z ^ (z >> 31)
    }
    fn below(&mut self, n: u64) -> u64 {
        self.next() % n
    }
    fn chance(&mut self, one_in: u64) -> bool {
        self.below(one_in) == 0
    }
    fn unit(&mut self) -> f64 {
        (self.next() >> 11) as f64 / 9007199254740992.0
    }
}

fn edge_f(r: &mut Rng) -> f32 {
    match r.below(32) {
        0 => 0.0,
        1 => -0.0,
        2 => 1.0,
        3 => -1.0,
        4 => f32::INFINITY,
        5 => f32::NEG_INFINITY,
        6 => f32::NAN,
        7 => f32::MAX,
        8 => f32::MIN,
        9 => f32::MIN_POSITIVE,
        10 => f32::from_bits(1),
        11 => -f32::from_bits(1),
        12 => f32::from_bits(r.below(0x800000) as u32),
        13 => 1e30,
        14 => -1e30,
        15 => 1e-30,
        16 => 16777216.0 + r.below(5) as f32 * 2.0,
        17 => 0.5,
        18 => (r.below(21) as i32 - 10) as f32,
        19 => (r.below(721) as i32 - 360) as f32,
        20 => f32::from_bits(r.next() as u32),
        21 | 22 => ((r.unit() * 2.0 - 1.0) * 1e6) as f32,
        _ => ((r.unit() * 2.0 - 1.0) * 1000.0) as f32,
    }
}

#[allow(dead_code)]
fn sane_f(r: &mut Rng) -> f32 {
    match r.below(16) {
        0 => 0.0,
        1 => -0.0,
        2 => 1.0,
        3 => (r.below(21) as i32 - 10) as f32,
        4 => ((r.unit() * 2.0 - 1.0) * 1e-3) as f32,
        _ => ((r.unit() * 2.0 - 1.0) * 200.0) as f32,
    }
}

fn edge_d(r: &mut Rng) -> f64 {
    match r.below(20) {
        0 => 0.0,
        1 => -0.0,
        2 => 1.0,
        3 => -1.0,
        4 => f64::INFINITY,
        5 => f64::NEG_INFINITY,
        6 => f64::NAN,
        7 => f64::MAX,
        8 => f64::MIN,
        9 => f64::from_bits(1),
        10 => f32::MAX as f64 * (1.0 + r.unit()),
        11 => -(f32::MAX as f64) * (1.0 + r.unit()),
        12 => f64::from_bits(r.next()),
        13 => 1e-300,
        _ => (r.unit() * 2.0 - 1.0) * 1e6,
    }
}

fn edge_i(r: &mut Rng, bits: u32) -> i64 {
    let max: i64 = if bits == 64 { i64::MAX } else { (1i64 << (bits - 1)) - 1 };
    let min = -max - 1;
    match r.below(12) {
        0 => 0,
        1 => 1,
        2 => -1,
        3 => min,
        4 => max,
        5 => min + 1,
        6 => max - 1,
        7 => max / 2 + r.below(5) as i64 - 2,
        8 => min / 2 + r.below(5) as i64 - 2,
        9 => r.below(201) as i64 - 100,
        _ => {
            let mut v = r.next();
            if bits < 64 {
                v &= (1u64 << bits) - 1;
                if v & (1u64 << (bits - 1)) != 0 {
                    v |= !((1u64 << bits) - 1);
                }
            }
            v as i64
        }
    }
}

// --------------------------------------------------------------- output -----

struct Out {
    line: String,
    sink: std::io::BufWriter<std::io::Stdout>,
    discard: bool,
}

impl Out {
    fn tag(&mut self, t: &str) {
        self.line.clear();
        self.line.push_str(t);
    }
    fn f(&mut self, v: f32) {
        use std::fmt::Write;
        let _ = write!(self.line, " {:08x}", v.to_bits());
    }
    fn d(&mut self, v: f64) {
        use std::fmt::Write;
        let _ = write!(self.line, " {:016x}", v.to_bits());
    }
    fn i(&mut self, v: i64) {
        use std::fmt::Write;
        let _ = write!(self.line, " {v}");
    }
    #[allow(dead_code)]
    fn u(&mut self, v: u64) {
        use std::fmt::Write;
        let _ = write!(self.line, " {v}");
    }
    fn b(&mut self, v: bool) {
        self.line.push_str(if v { " T" } else { " F" });
    }
    fn s(&mut self, s: &str) {
        self.line.push(' ');
        self.line.push_str(s);
    }
    fn arrow(&mut self) {
        self.line.push_str(" ->");
    }
    fn end(&mut self) {
        self.line.push('\n');
        if !self.discard {
            self.sink.write_all(self.line.as_bytes()).unwrap();
        }
    }
    fn ord<T: PartialOrd>(&mut self, a: T, b: T) {
        match a.partial_cmp(&b) {
            Some(std::cmp::Ordering::Less) => self.s("<"),
            Some(std::cmp::Ordering::Greater) => self.s(">"),
            Some(std::cmp::Ordering::Equal) => self.s("="),
            None => self.s("?"),
        }
    }
}

// ---------------------------------------------------------------- scalar ---

macro_rules! sat_int {
    ($o:expr, $r:expr, $t:ty, $name:expr, $bits:expr) => {{
        let a = edge_i($r, $bits) as $t;
        let b = edge_i($r, $bits) as $t;
        $o.tag($name);
        $o.i(a as i64);
        $o.i(b as i64);
        $o.arrow();
        $o.i(saturated::add(a, b) as i64);
        $o.i(saturated::sub(a, b) as i64);
        $o.f(saturated::average_scalar(a, b));
        $o.i(saturated::cast::<$t, $t>(a) as i64);
        $o.end();
    }};
}

macro_rules! cast_to_int {
    ($o:expr, $name:expr, $fp:ty, $si:ty, $v:expr, $print:ident) => {{
        let v: $fp = $v;
        if !v.is_nan() {
            $o.tag($name);
            $o.$print(v);
            $o.arrow();
            $o.i(saturated::cast::<$fp, $si>(v) as i64);
            $o.end();
        }
    }};
}

fn suite_scalar(r: &mut Rng, o: &mut Out, cases: i32) {
    o.tag("constants");
    for c in [
        kE, kLog2E, kLog10E, kLogE2, kLogE10, kPi, k2Pi, kPiOver2, kPiOver4, k1OverPi, k2OverPi,
        k2OverSqrtPi, kSqrt2, k1OverSqrt2, kSqrt2Over2, kPhi, kEhCloseEnough,
    ] {
        o.f(c);
    }
    o.end();
    for _ in 0..cases {
        let a = edge_f(r);
        let b = edge_f(r);
        let tol = if r.chance(2) { kEhCloseEnough } else { edge_f(r) };
        let da = edge_d(r);
        let ia = edge_i(r, 64);
        let ib = edge_i(r, 32) as i32;

        o.tag("abs");
        o.f(a);
        o.d(da);
        o.i(ia);
        o.i(ib as i64);
        o.arrow();
        o.f(absolute(a));
        o.d(absolute(da));
        o.i(absolute(ia));
        o.i(absolute(ib) as i64);
        o.end();

        o.tag("near");
        o.f(a);
        o.f(b);
        o.f(tol);
        o.arrow();
        o.b(scalar_nearly_zero(a));
        o.b(scalar_nearly_zero_tol(a, tol));
        o.b(scalar_nearly_equal(a, b));
        o.b(scalar_nearly_equal_tol(a, b, tol));
        o.end();

        let (ra, rb) = (Radians::new(a), Radians::new(b));
        o.tag("radians");
        o.f(a);
        o.f(b);
        o.arrow();
        o.b(ra.is_finite());
        o.f((-ra).radians);
        o.f((ra + rb).radians);
        o.f((ra - rb).radians);
        o.ord(ra, rb);
        o.b(ra == rb);
        o.b(ra < rb);
        o.b(ra >= rb);
        o.f(Radians::default().radians);
        o.end();

        let (dg, dh) = (Degrees::new(a), Degrees::new(b));
        o.tag("degrees");
        o.f(a);
        o.f(b);
        o.arrow();
        o.b(dg.is_finite());
        o.f(Radians::from(dg).radians);
        o.f((-dg).degrees);
        o.f((dg + dh).degrees);
        o.f((dg - dh).degrees);
        o.ord(dg, dh);
        o.b(dg == dh);
        o.b(dg > dh);
        o.f(dg.get_positive().degrees);
        o.end();

        sat_int!(o, r, i8, "sat8", 8);
        sat_int!(o, r, i16, "sat16", 16);
        sat_int!(o, r, i32, "sat32", 32);
        sat_int!(o, r, i64, "sat64", 64);

        let fa = edge_f(r);
        let fb = edge_f(r);
        let db = edge_d(r);
        o.tag("satf");
        o.f(fa);
        o.f(fb);
        o.d(da);
        o.d(db);
        o.arrow();
        o.f(saturated::add(fa, fb));
        o.f(saturated::sub(fa, fb));
        o.f(saturated::average_scalar(fa, fb));
        o.f(saturated::cast::<f32, f32>(fa));
        o.d(saturated::add(da, db));
        o.d(saturated::sub(da, db));
        o.f(saturated::average_scalar(da, db));
        o.d(saturated::cast::<f64, f64>(da));
        o.f(saturated::cast::<f64, f32>(da));
        o.d(saturated::cast::<f32, f64>(fa));
        o.end();

        cast_to_int!(o, "cast_f_i8", f32, i8, fa, f);
        cast_to_int!(o, "cast_f_i16", f32, i16, fa, f);
        cast_to_int!(o, "cast_f_i32", f32, i32, fa, f);
        cast_to_int!(o, "cast_f_i64", f32, i64, fa, f);
        cast_to_int!(o, "cast_d_i32", f64, i32, da, d);
        cast_to_int!(o, "cast_d_i64", f64, i64, da, d);
        let mut near = edge_i(r, 32) as f32;
        if r.chance(2) {
            near *= 2.0;
        }
        cast_to_int!(o, "cast_near_i32", f32, i32, near, f);
        cast_to_int!(o, "cast_near_i64", f32, i64, edge_i(r, 64) as f32, f);
        cast_to_int!(o, "cast_near_d_i64", f64, i64, edge_i(r, 64) as f64, d);
    }
}

// ----------------------------------------------------------------- main ----

type Suite = fn(&mut Rng, &mut Out, i32);
const SUITES: &[(&str, Suite)] = &[("scalar", suite_scalar)];

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 4 {
        eprintln!("usage: geometry_dump <suite> <seed> <cases> | bench <suite> <rounds>");
        std::process::exit(2);
    }
    let mut o = Out { line: String::new(), sink: std::io::BufWriter::new(std::io::stdout()), discard: false };
    if args[1] == "bench" {
        o.discard = true;
        let rounds: i32 = args[3].parse().unwrap();
        for (name, suite) in SUITES {
            if *name == args[2] {
                for i in 0..rounds {
                    let mut r = Rng { s: i as u64 + 1 };
                    suite(&mut r, &mut o, 20000);
                }
                return;
            }
        }
        eprintln!("unknown suite {}", args[2]);
        std::process::exit(2);
    }
    let mut r = Rng { s: args[2].parse().unwrap() };
    let cases: i32 = args[3].parse().unwrap();
    let mut known = false;
    for (name, suite) in SUITES {
        if args[1] == "all" || args[1] == *name {
            known = true;
            suite(&mut r, &mut o, cases);
        }
    }
    o.sink.flush().unwrap();
    if !known {
        eprintln!("unknown suite {}", args[1]);
        std::process::exit(2);
    }
}
