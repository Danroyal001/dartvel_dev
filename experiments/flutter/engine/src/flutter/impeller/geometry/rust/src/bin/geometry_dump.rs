// Not an upstream file: the port's side of the oracle (see
// oracle/geometry_dump.cc, which this mirrors suite by suite and line by line).
//
//   geometry_dump <suite> <seed> <cases>
//   geometry_dump bench <suite> <rounds>

#![allow(non_snake_case)]

use std::io::Write;

use impeller_geometry::arc::*;
use impeller_geometry::color::*;
use impeller_geometry::constants::*;
use impeller_geometry::dashed_line_path_source::*;
use impeller_geometry::path_source::*;
use impeller_geometry::half::*;
use impeller_geometry::matrix::*;
use impeller_geometry::matrix_decomposition::*;
use impeller_geometry::quaternion::*;
use impeller_geometry::gradient::*;
use impeller_geometry::rational::*;
use impeller_geometry::rect::*;
use impeller_geometry::round_rect::*;
use impeller_geometry::round_superellipse::*;
use impeller_geometry::round_superellipse_param::RoundSuperellipseParam;
use impeller_geometry::rounding_radii::*;
use impeller_geometry::rstransform::*;
use impeller_geometry::separated_vector::*;
use impeller_geometry::sigma::*;
use impeller_geometry::stroke_parameters::*;
use impeller_geometry::trig::*;
use impeller_geometry::wangs_formula::*;
use impeller_geometry::shear::*;
use impeller_geometry::vector::*;
use impeller_geometry::saturated;
use impeller_geometry::cxx::{self, Num};
use impeller_geometry::point::*;
use impeller_geometry::scalar::*;
use impeller_geometry::size::*;

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
    // A NaN prints as its class (see oracle/geometry_dump.cc).
    fn f(&mut self, v: f32) {
        if v.is_nan() {
            self.line.push_str(" nan");
            return;
        }
        use std::fmt::Write;
        let _ = write!(self.line, " {:08x}", v.to_bits());
    }
    fn d(&mut self, v: f64) {
        if v.is_nan() {
            self.line.push_str(" nan");
            return;
        }
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

// ------------------------------------------------------- point and size ---

fn small_f(r: &mut Rng) -> f32 {
    (r.unit() - 0.5) as f32
}

fn divisor_i(r: &mut Rng, bits: u32) -> i64 {
    let v = edge_i(r, bits);
    if v == 0 || v == -1 { 2 } else { v }
}

fn mod_i(r: &mut Rng) -> i64 {
    r.below(1 << 29) as i64 - (1 << 28)
}

fn edge_p(r: &mut Rng) -> Point {
    let x = edge_f(r);
    let y = edge_f(r);
    Point::new(x, y)
}
fn edge_s(r: &mut Rng) -> Size {
    let w = edge_f(r);
    let h = edge_f(r);
    Size::new(w, h)
}
fn edge_ip<T: Num>(r: &mut Rng, bits: u32) -> TPoint<T> {
    let x = T::from_i128(edge_i(r, bits) as i128);
    let y = T::from_i128(edge_i(r, bits) as i128);
    TPoint::new(x, y)
}
fn divisor_ip<T: Num>(r: &mut Rng, bits: u32) -> TPoint<T> {
    let x = T::from_i128(divisor_i(r, bits) as i128);
    let y = T::from_i128(divisor_i(r, bits) as i128);
    TPoint::new(x, y)
}
fn mod_ip(r: &mut Rng) -> IPoint {
    let x = mod_i(r);
    let y = mod_i(r);
    IPoint::new(x, y)
}

impl Out {
    fn p(&mut self, p: Point) {
        self.f(p.x);
        self.f(p.y);
    }
    fn ip<T: Num>(&mut self, p: TPoint<T>) {
        self.i(p.x.to_i128() as i64);
        self.i(p.y.to_i128() as i64);
    }
    fn sz(&mut self, s: Size) {
        self.f(s.width);
        self.f(s.height);
    }
    fn isz<T: Num>(&mut self, s: TSize<T>) {
        self.i(s.width.to_i128() as i64);
        self.i(s.height.to_i128() as i64);
    }
}

fn suite_point(r: &mut Rng, o: &mut Out, cases: i32) {
    for _ in 0..cases {
        let a = edge_p(r);
        let b = edge_p(r);
        let pc = edge_p(r);
        let s = edge_f(r);
        let ds = edge_d(r);
        let is = edge_i(r, 32) as i32;
        let sz = edge_s(r);

        o.tag("pt_ops");
        o.p(a);
        o.p(b);
        o.f(s);
        o.d(ds);
        o.i(is as i64);
        o.sz(sz);
        o.arrow();
        o.p(-a);
        o.p(a + b);
        o.p(a - b);
        o.p(a * b);
        o.p(a / b);
        o.p(a * s);
        o.p(a * ds);
        o.p(a * is);
        o.p(a / s);
        o.p(a / ds);
        o.p(a / is);
        o.p(s * a);
        o.p(ds * a);
        o.p(is * a);
        o.p(s / a);
        o.p(ds / a);
        o.p(is / a);
        o.p(a + sz);
        o.p(a - sz);
        o.p(a * sz);
        o.p(a / sz);
        o.p(sz + a);
        o.p(sz - a);
        o.p(sz * a);
        o.p(sz / a);
        o.p(a.sub_value(s));
        o.b(a == b);
        o.b(a != b);
        o.b(a == a);
        o.b(a != a);
        o.end();

        o.tag("pt_assign");
        let mut t = a;
        t += b;
        o.p(t);
        t = a;
        t += sz;
        o.p(t);
        t = a;
        t -= b;
        o.p(t);
        t = a;
        t -= sz;
        o.p(t);
        t = a;
        t *= b;
        o.p(t);
        t = a;
        t *= sz;
        o.p(t);
        t = a;
        t *= s;
        o.p(t);
        t = a;
        t *= ds;
        o.p(t);
        t = a;
        t *= is;
        o.p(t);
        t = a;
        t /= b;
        o.p(t);
        t = a;
        t /= sz;
        o.p(t);
        t = a;
        t /= s;
        o.p(t);
        t = a;
        t /= ds;
        o.p(t);
        t = a;
        t /= is;
        o.p(t);
        o.end();

        o.tag("pt_methods");
        o.p(a);
        o.p(b);
        o.p(pc);
        o.f(s);
        o.arrow();
        o.f(a.get_distance_squared(&b));
        o.p(a.min(&b));
        o.p(a.max(&b));
        o.p(a.floor());
        o.p(a.ceil());
        o.p(a.round());
        o.f(a.get_distance(&b));
        o.f(a.get_length_squared());
        o.f(a.get_length());
        o.f(a.get_distance_to_segment_squared(b, pc));
        o.f(a.get_distance_to_segment(b, pc));
        o.p(a.normalize());
        o.p(a.abs());
        o.f(a.cross(&b));
        o.f(Point::cross3(&a, &b, &pc));
        o.f(a.dot(&b));
        o.p(a.reflect(&b));
        o.p(a.rotate(&Radians::new(s)));
        o.p(a.perpendicular_right());
        o.p(a.perpendicular_left());
        o.f(a.angle_to(&b).radians);
        o.p(a.lerp(&b, s));
        o.b(a.is_zero());
        o.b(a.is_finite());
        o.p(Point::round_from(a));
        o.p(Point::make_xy(a.y, a.x));
        o.p(Point::from_size(sz));
        o.end();

        {
            let x0 = sane_f(r);
            let y0 = sane_f(r);
            let x1 = sane_f(r);
            let y1 = sane_f(r);
            let x2 = sane_f(r);
            let y2 = sane_f(r);
            let (p, p0, p1) = (Point::new(x0, y0), Point::new(x1, y1), Point::new(x2, y2));
            o.tag("pt_segment");
            o.p(p);
            o.p(p0);
            o.p(p1);
            o.arrow();
            o.f(p.get_distance_to_segment_squared(p0, p1));
            o.f(p.get_distance_to_segment(p0, p1));
            o.f(p.get_distance(&p0));
            o.p(p.normalize());
            o.f(p.angle_to(&p0).radians);
            o.end();
        }

        let ia: IPoint = edge_ip(r, 64);
        let ib: IPoint = edge_ip(r, 64);
        let id: IPoint = divisor_ip(r, 64);
        let ma = mod_ip(r);
        let mb = mod_ip(r);
        let mc = mod_ip(r);
        let dv = divisor_i(r, 64);
        let dv32 = divisor_i(r, 32) as i32;
        let fs = small_f(r);
        let dfs = small_f(r) as f64;
        let fd = (1.0 + r.unit()) as f32;
        let isz = {
            let w = edge_i(r, 64);
            let h = edge_i(r, 64);
            ISize::new(w, h)
        };
        let idsz = {
            let w = divisor_i(r, 64);
            let h = divisor_i(r, 64);
            ISize::new(w, h)
        };
        let mfx = sane_f(r) * 1000.0;
        let mfy = sane_f(r) * 1000.0;
        let mf = Point::new(mfx, mfy);

        o.tag("ipt_ops");
        o.ip(ia);
        o.ip(ib);
        o.ip(id);
        o.i(dv);
        o.i(dv32 as i64);
        o.f(fs);
        o.d(dfs);
        o.f(fd);
        o.isz(isz);
        o.arrow();
        o.ip(-ia);
        o.ip(ia + ib);
        o.ip(ia - ib);
        o.ip(ia * ib);
        o.ip(ia / id);
        o.ip(ia * dv);
        o.ip(ia * dv32);
        o.ip(ia * fs);
        o.ip(ia * dfs);
        o.ip(ia / dv);
        o.ip(ia / dv32);
        o.ip(ma / fd);
        o.ip(dv * ia);
        o.ip(fs * ia);
        o.ip(dv / id);
        o.ip(ia + isz);
        o.ip(ia - isz);
        o.ip(ia * isz);
        o.ip(ia / idsz);
        o.ip(isz + ia);
        o.ip(isz - ia);
        o.ip(isz / id);
        o.ip(ia.sub_value(dv));
        o.b(ia == ib);
        o.b(ia != ib);
        o.p(a + ia);
        o.p(ia + a);
        o.p(a - ia);
        o.p(ia - a);
        o.p(a * ia);
        o.p(ia * a);
        o.p(a / ia);
        o.p(ia / a);
        o.p(Point::from_point(ia));
        o.ip(IPoint::from_point(mf));
        o.ip(IPoint::round_from(mf));
        o.p(Point::round_from(ia));
        o.end();

        o.tag("ipt_assign");
        let mut it = ia;
        it += ib;
        o.ip(it);
        it = ia;
        it += isz;
        o.ip(it);
        it = ia;
        it -= ib;
        o.ip(it);
        it = ia;
        it *= ib;
        o.ip(it);
        it = ia;
        it *= dv32;
        o.ip(it);
        it = ia;
        it /= id;
        o.ip(it);
        it = ia;
        it /= dv;
        o.ip(it);
        it = ia;
        it /= idsz;
        o.ip(it);
        o.end();

        o.tag("ipt_methods");
        o.ip(ma);
        o.ip(mb);
        o.ip(mc);
        o.f(fs);
        o.arrow();
        o.i(ma.get_distance_squared(&mb));
        o.i(ma.get_distance(&mb));
        o.i(ma.get_distance_to_segment_squared(mb, mc));
        o.i(ma.get_distance_to_segment(mb, mc));
        o.ip(ma.lerp(&mb, fs));
        o.ip(ia.min(&ib));
        o.ip(ia.max(&ib));
        o.f(ia.get_length_squared());
        o.f(ia.get_length());
        o.i(ia.cross(&ib));
        o.i(IPoint::cross3(&ia, &ib, &id));
        o.i(ia.dot(&ib));
        o.ip(ia.reflect(&ib));
        o.ip(ia.perpendicular_right());
        o.ip(ia.perpendicular_left());
        o.b(ia.is_zero());
        o.b(IPoint::default().is_zero());
        o.end();

        let ja: IPoint32 = edge_ip(r, 32);
        let jb: IPoint32 = edge_ip(r, 32);
        let jd: IPoint32 = divisor_ip(r, 32);
        let ua: UintPoint32 = edge_ip(r, 32);
        let ub: UintPoint32 = edge_ip(r, 32);
        let ud: UintPoint32 = divisor_ip(r, 32);
        let j64 = edge_i(r, 64);
        o.tag("ipt32");
        o.ip(ja);
        o.ip(jb);
        o.ip(jd);
        o.ip(ua);
        o.ip(ub);
        o.ip(ud);
        o.i(j64);
        o.arrow();
        o.ip(-ja);
        o.ip(ja + jb);
        o.ip(ja - jb);
        o.ip(ja * jb);
        o.ip(ja / jd);
        o.ip(ja * j64);
        o.ip(ja * dv32);
        o.ip(ja * fs);
        o.ip(ja / dv32);
        o.ip(ja.sub_value(jb.x));
        o.i(ja.cross(&jb) as i64);
        o.i(ja.dot(&jb) as i64);
        o.f(ja.get_length_squared());
        o.ip(ja.min(&jb));
        o.ip(ja.max(&jb));
        o.p(a + ja);
        o.p(ja - a);
        o.p(a / ja);
        o.ip(-ua);
        o.ip(ua + ub);
        o.ip(ua - ub);
        o.ip(ua * ub);
        o.ip(ua / ud);
        o.ip(ua * dv32);
        o.ip(ua / dv32);
        o.ip(ua * j64);
        o.i(ua.cross(&ub) as i64);
        o.i(ua.dot(&ub) as i64);
        o.f(ua.get_length_squared());
        o.ip(ua.min(&ub));
        o.ip(ua.max(&ub));
        o.ip(ua.perpendicular_left());
        o.p(a * ua);
        o.p(Point::from_point(ua));
        o.ip(IPoint32::from_point(ia));
        o.ip(UintPoint32::from_point(ja));
        o.end();
    }
}

fn mip_count_defined(s: Size) -> bool {
    s.is_empty()
        || (cxx::min(s.width, s.height) > 0.5 && !(s.width.is_infinite() && s.height.is_infinite()))
}

fn suite_size(r: &mut Rng, o: &mut Out, cases: i32) {
    for _ in 0..cases {
        let a = edge_s(r);
        let b = edge_s(r);
        let s = edge_f(r);
        let ds = edge_d(r);
        let is = edge_i(r, 32) as i32;

        o.tag("size_ops");
        o.sz(a);
        o.sz(b);
        o.f(s);
        o.d(ds);
        o.i(is as i64);
        o.arrow();
        o.sz(a * s);
        o.sz(a / s);
        o.sz(a / b);
        o.sz(a + b);
        o.sz(a - b);
        o.sz(-a);
        o.sz(s * a);
        o.sz(ds * a);
        o.sz(is * a);
        o.sz(s / a);
        o.sz(ds / a);
        o.sz(is / a);
        let mut t = a;
        t *= s;
        o.sz(t);
        t = a;
        t *= ds;
        o.sz(t);
        t = a;
        t *= is;
        o.sz(t);
        o.b(a == b);
        o.b(a != b);
        o.b(a == a);
        o.end();

        o.tag("size_methods");
        o.sz(a);
        o.sz(b);
        o.arrow();
        o.sz(a.min(&b));
        o.sz(a.max(&b));
        o.f(a.min_dimension());
        o.f(a.max_dimension());
        o.sz(a.abs());
        o.sz(a.floor());
        o.sz(a.ceil());
        o.sz(a.round());
        o.f(a.area());
        o.b(a.is_empty());
        o.b(a.is_finite());
        o.b(a.is_square());
        o.sz(Size::ceil_from(a));
        if mip_count_defined(a) {
            o.u(a.mip_count() as u64);
        }
        o.sz(Size::splat(s));
        o.sz(Size::make_wh(s, a.width));
        o.sz(Size::infinite());
        o.sz(Size::default());
        o.end();

        let ia = {
            let w = edge_i(r, 64);
            let h = edge_i(r, 64);
            ISize::new(w, h)
        };
        let ib = {
            let w = edge_i(r, 64);
            let h = edge_i(r, 64);
            ISize::new(w, h)
        };
        let id = {
            let w = divisor_i(r, 64);
            let h = divisor_i(r, 64);
            ISize::new(w, h)
        };
        let mw = mod_i(r);
        let mh = mod_i(r);
        let ja = {
            let w = edge_i(r, 32) as i32;
            let h = edge_i(r, 32) as i32;
            ISize32::new(w, h)
        };
        let jb = {
            let w = edge_i(r, 32) as i32;
            let h = edge_i(r, 32) as i32;
            ISize32::new(w, h)
        };
        let mfw = sane_f(r) * 1000.0;
        let mfh = sane_f(r) * 1000.0;
        o.tag("isize");
        o.isz(ia);
        o.isz(ib);
        o.isz(id);
        o.i(mw);
        o.i(mh);
        o.isz(ja);
        o.isz(jb);
        o.f(mfw);
        o.f(mfh);
        o.arrow();
        o.isz(ia + ib);
        o.isz(ia - ib);
        o.isz(-ia);
        o.isz(ia / id);
        o.i(ia.area());
        o.isz(ia.min(&ib));
        o.isz(ia.max(&ib));
        o.i(ia.min_dimension());
        o.i(ia.max_dimension());
        o.b(ia.is_empty());
        o.b(ia.is_square());
        o.b(ia == ib);
        o.b(ia != ib);
        o.u(ia.mip_count() as u64);
        o.u(ISize::new(mw, mh).mip_count() as u64);
        let mut it = ia;
        it *= is;
        o.isz(it);
        o.isz(ISize::ceil_from(Size::new(mfw, mfh)));
        o.isz(ISize::from_size(Size::new(mfw, mfh)));
        o.sz(Size::from_size(ia));
        o.isz(ISize::infinite());
        o.isz(ja + jb);
        o.isz(ja - jb);
        o.i(ja.area() as i64);
        o.isz(ISize32::from_size(ia));
        o.u(ja.mip_count() as u64);
        o.end();
    }
}

// ------------------------------------------------- vector, color, half ---

fn edge_v3(r: &mut Rng) -> Vector3 {
    let x = edge_f(r);
    let y = edge_f(r);
    let z = edge_f(r);
    Vector3::new(x, y, z)
}
fn edge_v4(r: &mut Rng) -> Vector4 {
    let x = edge_f(r);
    let y = edge_f(r);
    let z = edge_f(r);
    let w = edge_f(r);
    Vector4::new(x, y, z, w)
}

impl Out {
    fn v3(&mut self, v: Vector3) {
        self.f(v.x);
        self.f(v.y);
        self.f(v.z);
    }
    fn v4(&mut self, v: Vector4) {
        self.f(v.x);
        self.f(v.y);
        self.f(v.z);
        self.f(v.w);
    }
    fn c(&mut self, c: Color) {
        self.f(c.red);
        self.f(c.green);
        self.f(c.blue);
        self.f(c.alpha);
    }
}

fn suite_vector(r: &mut Rng, o: &mut Out, cases: i32) {
    for _ in 0..cases {
        let a = edge_v3(r);
        let b = edge_v3(r);
        let s = edge_f(r);
        let ds = edge_d(r);
        let is = edge_i(r, 32) as i32;
        let p = edge_p(r);
        let sz = edge_s(r);
        o.tag("v3_ops");
        o.v3(a);
        o.v3(b);
        o.f(s);
        o.d(ds);
        o.i(is as i64);
        o.arrow();
        o.v3(-a);
        o.v3(a + b);
        o.v3(a - b);
        o.v3(a + s);
        o.v3(a - s);
        o.v3(a * b);
        o.v3(a * s);
        o.v3(a * ds);
        o.v3(a * is);
        o.v3(a / b);
        o.v3(a / s);
        o.v3(a / ds);
        o.v3(a / is);
        o.v3(s * a);
        o.v3(ds * a);
        o.v3(is * a);
        o.v3(s + a);
        o.v3(ds + a);
        o.v3(is + a);
        o.v3(s - a);
        o.v3(ds - a);
        o.v3(is - a);
        o.v3(s / a);
        o.v3(ds / a);
        o.v3(is / a);
        let mut t = a;
        t += b;
        o.v3(t);
        t = a;
        t -= b;
        o.v3(t);
        t = a;
        t *= b;
        o.v3(t);
        t = a;
        t *= s;
        o.v3(t);
        t = a;
        t *= ds;
        o.v3(t);
        t = a;
        t *= is;
        o.v3(t);
        t = a;
        t /= b;
        o.v3(t);
        t = a;
        t /= s;
        o.v3(t);
        t = a;
        t /= ds;
        o.v3(t);
        t = a;
        t /= is;
        o.v3(t);
        o.b(a == b);
        o.b(a != b);
        o.b(a == a);
        o.end();

        o.tag("v3_methods");
        o.v3(a);
        o.v3(b);
        o.f(s);
        o.arrow();
        o.f(a.get_length());
        o.v3(a.normalize());
        o.f(a.dot(&b));
        o.v3(a.abs());
        o.v3(a.cross(&b));
        o.v3(a.min(&b));
        o.v3(a.max(&b));
        o.v3(a.floor());
        o.v3(a.ceil());
        o.v3(a.round());
        o.v3(a.lerp(&b, s));
        o.v3(Vector3::combine(&a, s, &b, b.x));
        o.v3(Vector3::from(p));
        o.v3(Vector3::from(sz));
        o.v3(Vector3::new2(s, a.x));
        o.v3(Vector3::default());
        o.end();

        let u = edge_v4(r);
        let v = edge_v4(r);
        let f0 = edge_f(r);
        let f1 = edge_f(r);
        let f2 = edge_f(r);
        let f3 = edge_f(r);
        o.tag("v4");
        o.v4(u);
        o.v4(v);
        o.f(s);
        o.arrow();
        o.b(u.is_finite());
        o.v4(u.normalize());
        o.b(u == v);
        o.b(u != v);
        o.b(u == u);
        o.v4(u + v);
        o.v4(u - v);
        o.v4(u * s);
        o.v4(u * v);
        o.v4(u.min(&v));
        o.v4(u.max(&v));
        o.v4(u.floor());
        o.v4(u.ceil());
        o.v4(u.round());
        o.v4(u.lerp(&v, s));
        o.p(u.xy());
        o.v4(Vector4::default());
        o.v4(Vector4::from(a));
        o.v4(Vector4::from(p));
        o.v4(Vector4::from([f0, f1, f2, f3]));
        o.end();
    }
}

fn comp_f(r: &mut Rng) -> f32 {
    match r.below(10) {
        0 => 0.0,
        1 => 1.0,
        2 => edge_f(r),
        3 => (r.unit() * 3.0 - 1.0) as f32,
        _ => r.unit() as f32,
    }
}
fn comp_c(r: &mut Rng) -> Color {
    let red = comp_f(r);
    let green = comp_f(r);
    let blue = comp_f(r);
    let alpha = comp_f(r);
    Color::new(red, green, blue, alpha)
}
fn unit_c(r: &mut Rng) -> Color {
    let red = r.unit() as f32;
    let green = r.unit() as f32;
    let blue = r.unit() as f32;
    let alpha = r.unit() as f32;
    Color::new(red, green, blue, alpha)
}

fn suite_color(r: &mut Rng, o: &mut Out, cases: i32) {
    o.tag("named");
    o.c(Color::white());
    o.c(Color::black());
    o.c(Color::white_transparent());
    o.c(Color::black_transparent());
    o.c(Color::red());
    o.c(Color::green());
    o.c(Color::blue());
    o.c(Color::alice_blue());
    o.c(Color::antique_white());
    o.c(Color::aqua());
    o.c(Color::aqua_marine());
    o.c(Color::azure());
    o.c(Color::beige());
    o.c(Color::bisque());
    o.c(Color::blanched_almond());
    o.c(Color::blue_violet());
    o.c(Color::brown());
    o.c(Color::burly_wood());
    o.c(Color::cadet_blue());
    o.c(Color::chartreuse());
    o.c(Color::chocolate());
    o.c(Color::coral());
    o.c(Color::cornflower_blue());
    o.c(Color::cornsilk());
    o.c(Color::crimson());
    o.c(Color::cyan());
    o.c(Color::dark_blue());
    o.c(Color::dark_cyan());
    o.c(Color::dark_goldenrod());
    o.c(Color::dark_gray());
    o.c(Color::dark_green());
    o.c(Color::dark_grey());
    o.c(Color::dark_khaki());
    o.c(Color::dark_magenta());
    o.c(Color::dark_olive_green());
    o.c(Color::dark_orange());
    o.c(Color::dark_orchid());
    o.c(Color::dark_red());
    o.c(Color::dark_salmon());
    o.c(Color::dark_seagreen());
    o.c(Color::dark_slate_blue());
    o.c(Color::dark_slate_gray());
    o.c(Color::dark_slate_grey());
    o.c(Color::dark_turquoise());
    o.c(Color::dark_violet());
    o.c(Color::deep_pink());
    o.c(Color::deep_sky_blue());
    o.c(Color::dim_gray());
    o.c(Color::dim_grey());
    o.c(Color::dodger_blue());
    o.c(Color::firebrick());
    o.c(Color::floral_white());
    o.c(Color::forest_green());
    o.c(Color::fuchsia());
    o.c(Color::gainsboro());
    o.c(Color::ghostwhite());
    o.c(Color::gold());
    o.c(Color::goldenrod());
    o.c(Color::gray());
    o.c(Color::green_yellow());
    o.c(Color::grey());
    o.c(Color::honeydew());
    o.c(Color::hot_pink());
    o.c(Color::indian_red());
    o.c(Color::indigo());
    o.c(Color::ivory());
    o.c(Color::khaki());
    o.c(Color::lavender());
    o.c(Color::lavender_blush());
    o.c(Color::lawn_green());
    o.c(Color::lemon_chiffon());
    o.c(Color::light_blue());
    o.c(Color::light_coral());
    o.c(Color::light_cyan());
    o.c(Color::light_goldenrod_yellow());
    o.c(Color::light_gray());
    o.c(Color::light_green());
    o.c(Color::light_grey());
    o.c(Color::light_pink());
    o.c(Color::light_salmon());
    o.c(Color::light_sea_green());
    o.c(Color::light_sky_blue());
    o.c(Color::light_slate_gray());
    o.c(Color::light_slate_grey());
    o.c(Color::light_steel_blue());
    o.c(Color::light_yellow());
    o.c(Color::lime());
    o.c(Color::lime_green());
    o.c(Color::linen());
    o.c(Color::magenta());
    o.c(Color::maroon());
    o.c(Color::medium_aquamarine());
    o.c(Color::medium_blue());
    o.c(Color::medium_orchid());
    o.c(Color::medium_purple());
    o.c(Color::medium_seagreen());
    o.c(Color::medium_slate_blue());
    o.c(Color::medium_spring_green());
    o.c(Color::medium_turquoise());
    o.c(Color::medium_violet_red());
    o.c(Color::midnight_blue());
    o.c(Color::mint_cream());
    o.c(Color::misty_rose());
    o.c(Color::moccasin());
    o.c(Color::navajo_white());
    o.c(Color::navy());
    o.c(Color::old_lace());
    o.c(Color::olive());
    o.c(Color::olive_drab());
    o.c(Color::orange());
    o.c(Color::orange_red());
    o.c(Color::orchid());
    o.c(Color::pale_goldenrod());
    o.c(Color::pale_green());
    o.c(Color::pale_turquoise());
    o.c(Color::pale_violet_red());
    o.c(Color::papaya_whip());
    o.c(Color::peachpuff());
    o.c(Color::peru());
    o.c(Color::pink());
    o.c(Color::plum());
    o.c(Color::powder_blue());
    o.c(Color::purple());
    o.c(Color::rosy_brown());
    o.c(Color::royal_blue());
    o.c(Color::saddle_brown());
    o.c(Color::salmon());
    o.c(Color::sandy_brown());
    o.c(Color::seagreen());
    o.c(Color::seashell());
    o.c(Color::sienna());
    o.c(Color::silver());
    o.c(Color::sky_blue());
    o.c(Color::slate_blue());
    o.c(Color::slate_gray());
    o.c(Color::slate_grey());
    o.c(Color::snow());
    o.c(Color::spring_green());
    o.c(Color::steel_blue());
    o.c(Color::tan());
    o.c(Color::teal());
    o.c(Color::thistle());
    o.c(Color::tomato());
    o.c(Color::turquoise());
    o.c(Color::violet());
    o.c(Color::wheat());
    o.c(Color::whitesmoke());
    o.c(Color::yellow());
    o.c(Color::yellow_green());
    o.end();
    o.tag("blend_modes");
    for m in 0..=BlendMode::kLastMode as u8 {
        o.s(blend_mode_to_string(BlendMode::from_u8(m).unwrap()));
    }
    o.i(BlendMode::kDefaultMode as i64);
    o.end();
    for _ in 0..cases {
        let a = comp_c(r);
        let b = comp_c(r);
        let s = edge_f(r);
        let ds = edge_d(r);
        let is = edge_i(r, 32) as i32;
        o.tag("color_ops");
        o.c(a);
        o.c(b);
        o.f(s);
        o.d(ds);
        o.i(is as i64);
        o.arrow();
        o.c(a + b);
        o.c(a + s);
        o.c(a + ds);
        o.c(a + is);
        o.c(a - b);
        o.c(a - s);
        o.c(a - is);
        o.c(a * b);
        o.c(a * s);
        o.c(a * ds);
        o.c(a * is);
        o.c(a / b);
        o.c(a / s);
        o.c(a / is);
        o.c(s + a);
        o.c(ds - a);
        o.c(is * a);
        o.c(s / a);
        o.b(a == b);
        o.b(a == a);
        o.c(a.premultiply());
        o.c(a.unpremultiply());
        o.b(a.is_wide_gamut());
        o.c(Color::lerp(a, b, s));
        o.c(a.clamp01());
        o.c(a.with_alpha(s));
        o.u(Color::to_i_color(a) as u64);
        o.c(a.linear_to_srgb());
        o.c(a.srgb_to_linear());
        o.b(a.is_transparent());
        o.b(a.is_opaque());
        o.c(Color::from(Vector4::from(a)));
        o.v3(Vector3::from(a));
        o.end();

        o.tag("blend");
        o.c(a);
        o.c(b);
        o.arrow();
        for m in 0..=BlendMode::kLastMode as u8 {
            o.c(a.blend(b, BlendMode::from_u8(m).unwrap()));
        }
        o.end();

        let mut cm = ColorMatrix::default();
        for i in 0..20 {
            cm.array[i] = if r.chance(4) { edge_f(r) } else { (r.unit() * 2.0 - 1.0) as f32 };
        }
        o.tag("matrix");
        for i in 0..20 {
            o.f(cm.array[i]);
        }
        o.arrow();
        o.c(a.apply_color_matrix(&cm));
        o.end();

        let u = unit_c(r);
        let r8 = r.below(256) as u8;
        let g8 = r.below(256) as u8;
        let b8 = r.below(256) as u8;
        let a8 = r.below(256) as u8;
        o.tag("color8");
        o.c(u);
        o.i(r8 as i64);
        o.i(g8 as i64);
        o.i(b8 as i64);
        o.i(a8 as i64);
        o.arrow();
        let bytes = u.to_r8g8b8a8();
        o.i(bytes[0] as i64);
        o.i(bytes[1] as i64);
        o.i(bytes[2] as i64);
        o.i(bytes[3] as i64);
        o.u(u.to_argb() as u64);
        o.u(Color::to_i_color(u) as u64);
        o.c(Color::make_rgba8(r8, g8, b8, a8));
        o.end();

        let h0 = (r.unit() * 65536.0 - 0.99) as f32;
        let h1 = (r.unit() * 65536.0) as f32;
        let h2 = (r.unit() * 100.0) as f32;
        let h3 = r.unit() as f32;
        let hd = r.unit() * 65535.0;
        let hi = r.below(65536) as i32;
        o.tag("half");
        o.f(h0);
        o.f(h1);
        o.f(h2);
        o.f(h3);
        o.d(hd);
        o.i(hi as i64);
        o.arrow();
        o.i(scalar_to_half(h0) as i64);
        o.i(Half::from_scalar(h1).x as i64);
        o.i(Half::from_f64(hd).x as i64);
        o.i(Half::from_int(hi).x as i64);
        o.i(Half::from_internal(hi as InternalHalf).x as i64);
        o.b(Half::from_scalar(h1) == Half::from_scalar(h2));
        let hv4 = HalfVector4::from(Color::new(h0, h1, h2, h3));
        let hw4 = HalfVector4::from(Vector4::new(h3, h2, h1, h0));
        let hv3 = HalfVector3::from(Vector3::new(h0, h1, h2));
        let hv2 = HalfVector2::from(Vector2::new(h2, h3));
        o.i(hv4.x as i64);
        o.i(hv4.y as i64);
        o.i(hv4.z as i64);
        o.i(hv4.w as i64);
        o.i(hw4.x as i64);
        o.i(hw4.w as i64);
        o.i(hv3.x as i64);
        o.i(hv3.y as i64);
        o.i(hv3.z as i64);
        o.i(hv2.x as i64);
        o.i(hv2.y as i64);
        o.b(hv4 == hw4);
        o.b(hv4 != hw4);
        o.b(hv3 == HalfVector3::new(hv3.x, hv3.y, hv3.z));
        o.b(hv2 != HalfVector2::new(hv2.y, hv2.x));
        o.end();
    }
}

// ---------------------------------------------------------------- matrix ---

impl Out {
    fn m(&mut self, m: &Matrix) {
        for i in 0..16 {
            self.f(m.m[i]);
        }
    }
    fn q(&mut self, q: &Quaternion) {
        self.f(q.x);
        self.f(q.y);
        self.f(q.z);
        self.f(q.w);
    }
    fn opt_f(&mut self, v: Option<Scalar>) {
        match v {
            Some(v) => self.f(v),
            None => self.s("none"),
        }
    }
    fn decomp(&mut self, d: &MatrixDecomposition) {
        self.v3(d.translation);
        self.v3(d.scale);
        self.d(d.shear.xy);
        self.d(d.shear.xz);
        self.d(d.shear.yz);
        self.v4(d.perspective);
        self.q(&d.rotation);
        self.u(d.get_components_mask());
    }
}

fn sane_p(r: &mut Rng) -> Point {
    let x = sane_f(r);
    let y = sane_f(r);
    Point::new(x, y)
}

fn sane_v3(r: &mut Rng) -> Vector3 {
    let x = sane_f(r);
    let y = sane_f(r);
    let z = sane_f(r);
    Vector3::new(x, y, z)
}

fn gen_m(r: &mut Rng) -> Matrix {
    let mut m = Matrix::default();
    match r.below(10) {
        0 => {
            for i in 0..16 {
                m.m[i] = edge_f(r);
            }
            m
        }
        1 => {
            for i in 0..16 {
                m.m[i] = sane_f(r);
            }
            m
        }
        2 => {
            let a = sane_f(r);
            let b = sane_f(r);
            let c = sane_f(r);
            let d = sane_f(r);
            let tx = sane_f(r);
            let ty = sane_f(r);
            Matrix::new(a, b, 0.0, 0.0, c, d, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, tx, ty, 0.0, 1.0)
        }
        3 => {
            let s = sane_v3(r);
            let t = sane_v3(r);
            Matrix::make_translate_scale(s, t)
        }
        4 => {
            let t = sane_v3(r);
            let angle = sane_f(r);
            let s = sane_v3(r);
            let kx = sane_f(r) * 0.01;
            let ky = sane_f(r) * 0.01;
            Matrix::make_translation(t)
                * Matrix::make_rotation_z(Radians::new(angle))
                * Matrix::make_scale(s)
                * Matrix::make_skew(kx, ky)
        }
        5 => {
            for i in 0..16 {
                m.m[i] = sane_f(r) * 0.01;
            }
            m.m[0] += 1.0;
            m.m[5] += 1.0;
            m.m[10] += 1.0;
            m.m[15] += 1.0;
            m
        }
        6 => {
            for i in 0..16 {
                m.m[i] = sane_f(r);
            }
            let a = r.below(4) as usize;
            let b = r.below(4) as usize;
            let k = sane_f(r);
            for j in 0..4 {
                *m.e_mut(a, j) = m.e(b, j) * k;
            }
            m
        }
        7 => {
            for i in 0..16 {
                m.m[i] = sane_f(r);
            }
            let a = r.below(4) as usize;
            let b = (a + 1 + r.below(3) as usize) % 4;
            for j in 0..4 {
                let eps = ((r.unit() - 0.5) * 1e-5) as f32;
                *m.e_mut(a, j) = m.e(b, j) + eps;
            }
            m
        }
        8 => {
            let angle = edge_f(r);
            let x = sane_f(r);
            let y = sane_f(r);
            let z = sane_f(r);
            let t = sane_v3(r);
            Matrix::make_translation(t)
                * Matrix::make_rotation_axis(Radians::new(angle), &Vector4::new(x, y, z, 1.0))
        }
        _ => {
            let n = r.below(4);
            for _ in 0..n {
                let k = r.below(16) as usize;
                m.m[k] = if r.chance(2) { edge_f(r) } else { 0.0 };
            }
            m
        }
    }
}

fn gen_q(r: &mut Rng) -> Quaternion {
    if r.chance(4) {
        let x = edge_f(r);
        let y = edge_f(r);
        let z = edge_f(r);
        let w = edge_f(r);
        return Quaternion::new(x, y, z, w);
    }
    let axis = sane_v3(r);
    let angle = sane_f(r);
    Quaternion::from_axis_angle(&axis.normalize(), angle)
}

fn suite_matrix(r: &mut Rng, o: &mut Out, cases: i32) {
    for _ in 0..cases {
        let a = gen_m(r);
        let b = gen_m(r);
        let v3 = if r.chance(3) { edge_v3(r) } else { sane_v3(r) };
        let v4 = edge_v4(r);
        let p = if r.chance(3) { edge_p(r) } else { sane_p(r) };
        let s = if r.chance(3) { edge_f(r) } else { sane_f(r) };
        let tol = if r.chance(2) { kEhCloseEnough } else { sane_f(r) };

        o.tag("mx_ops");
        o.m(&a);
        o.m(&b);
        o.v3(v3);
        o.v4(v4);
        o.p(p);
        o.arrow();
        o.m(&a.basis());
        o.m(&a.to3x3());
        o.m(&a.translate(&v3));
        o.m(&a.scale(&v3));
        o.m(&a.multiply(&b));
        o.m(&(a * b));
        o.m(&(a + b));
        o.m(&(a + v3));
        o.m(&(a - v3));
        o.m(&a.transpose());
        o.m(&a.invert());
        o.f(a.get_determinant());
        o.b(a.is_invertible());
        o.v4(a * v4);
        o.v3(a * v3);
        o.p(a * p);
        o.v3(a.transform_homogenous(&p));
        o.v4(a.transform_direction4(&v4));
        o.v3(a.transform_direction3(&v3));
        o.p(a.transform_direction2(&p));
        let quad: Quad = [p, Point::new(v3.x, v3.y), Point::new(v4.x, v4.y), Point::new(s, s)];
        let tq = a.transform(&quad);
        for qp in tq {
            o.p(qp);
        }
        o.b(a == b);
        o.b(a != b);
        o.b(a == a);
        o.b(a.equals(&b));
        o.b(a.equals_eps(&b, tol));
        o.end();

        o.tag("mx_query");
        o.m(&a);
        o.f(tol);
        o.v3(v3);
        o.arrow();
        o.f(a.get_max_basis_length_xy());
        o.opt_f(a.get_min_scale_2d());
        o.opt_f(a.get_max_scale_2d());
        match a.get_scales_2d() {
            Some((x, y)) => {
                o.f(x);
                o.f(y);
            }
            None => o.s("none"),
        }
        o.v3(a.get_basis_x());
        o.v3(a.get_basis_y());
        o.v3(a.get_basis_z());
        o.v3(a.get_scale());
        o.p(a.get_basis_x_2d());
        o.p(a.get_basis_y_2d());
        o.p(a.get_basis_scale_xy());
        o.p(a.get_transformed_pixel_size());
        o.f(a.get_direction_scale(v3));
        o.b(a.is_finite());
        o.b(a.is_affine());
        o.b(a.has_perspective_2d());
        o.b(a.has_perspective());
        o.b(a.has_translation());
        o.b(a.is_aligned_2d());
        o.b(a.is_aligned_2d_tol(tol));
        o.b(a.is_aligned());
        o.b(a.is_aligned_tol(tol));
        o.b(a.is_identity());
        o.b(a.is_translation_only());
        o.b(a.is_translation_scale_only());
        o.end();

        o.tag("mx_decompose");
        o.m(&a);
        o.arrow();
        match a.decompose() {
            Some(d) => {
                o.decomp(&d);
                o.m(&Matrix::from_decomposition(&d));
            }
            None => o.s("none"),
        }
        o.end();

        let mut rd = MatrixDecomposition::default();
        rd.translation = sane_v3(r);
        rd.scale = sane_v3(r);
        {
            let xy = if r.chance(2) { 0.0 } else { r.unit() - 0.5 };
            let xz = if r.chance(2) { 0.0 } else { r.unit() - 0.5 };
            let yz = if r.chance(2) { 0.0 } else { r.unit() - 0.5 };
            rd.shear = Shear::new(xy, xz, yz);
        }
        if r.chance(2) {
            let px = sane_f(r) * 0.01;
            let py = sane_f(r) * 0.01;
            let pz = sane_f(r) * 0.01;
            rd.perspective = Vector4::new(px, py, pz, 1.0);
        }
        rd.rotation = gen_q(r);
        o.tag("mx_recompose");
        o.decomp(&rd);
        o.arrow();
        o.m(&Matrix::from_decomposition(&rd));
        o.u(MatrixDecomposition::default().get_components_mask());
        o.b(Shear::new(rd.shear.xy, 0.0, 0.0) == rd.shear);
        o.end();

        let mut f = [0.0f32; 16];
        for v in f.iter_mut() {
            *v = edge_f(r);
        }
        let q = gen_q(r);
        let q2 = gen_q(r);
        let angle = if r.chance(3) { edge_f(r) } else { sane_f(r) };
        let sx = sane_f(r);
        let sy = sane_f(r);
        let eye = sane_v3(r);
        let target = sane_v3(r);
        let up = sane_v3(r);
        let fov = sane_f(r);
        let aspect = sane_f(r);
        let znear = sane_f(r);
        let zfar = sane_f(r);
        let osz = edge_s(r);
        let iosz = {
            let w = edge_i(r, 64);
            let h = edge_i(r, 64);
            ISize::new(w, h)
        };
        let t = if r.chance(4) { edge_d(r) } else { r.unit() };
        o.tag("mx_make");
        for v in f {
            o.f(v);
        }
        o.q(&q);
        o.q(&q2);
        o.f(angle);
        o.arrow();
        o.m(&Matrix::make_column(
            f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8], f[9], f[10], f[11], f[12], f[13],
            f[14], f[15],
        ));
        o.m(&Matrix::make_row(
            f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8], f[9], f[10], f[11], f[12], f[13],
            f[14], f[15],
        ));
        o.m(&Matrix::make_translation(v3));
        o.m(&Matrix::make_scale(v3));
        o.m(&Matrix::make_translate_scale(v3, Vector3::new(f[0], f[1], f[2])));
        o.m(&Matrix::make_scale2(Vector2::new(f[3], f[4])));
        o.m(&Matrix::make_skew(sx, sy));
        o.m(&Matrix::make_rotation(q));
        o.m(&Matrix::make_rotation_axis(Radians::new(angle), &v4));
        o.m(&Matrix::make_rotation_x(Radians::new(angle)));
        o.m(&Matrix::make_rotation_y(Radians::new(angle)));
        o.m(&Matrix::make_rotation_z(Radians::new(angle)));
        o.p(Matrix::cos_sin(Radians::new(angle)));
        o.m(&Matrix::make_orthographic(osz));
        o.m(&Matrix::make_orthographic(iosz));
        o.m(&Matrix::make_perspective(Radians::new(fov), aspect, znear, zfar));
        o.m(&Matrix::make_perspective_size(Radians::new(fov), osz, znear, zfar));
        o.m(&Matrix::make_perspective_size(Radians::new(fov), iosz, znear, zfar));
        o.m(&Matrix::make_look_at(eye, target, up));
        o.m(&Matrix::default());
        o.end();

        o.tag("quaternion");
        o.q(&q);
        o.q(&q2);
        o.v3(v3);
        o.f(s);
        o.d(t);
        o.arrow();
        o.f(q.dot(&q2));
        o.f(q.length());
        o.q(&q.normalize());
        o.q(&q.invert());
        o.q(&q.slerp(&q2, t));
        o.q(&(q * q2));
        o.q(&(q * s));
        o.v3(q * v3);
        o.q(&(q + q2));
        o.q(&(q - q2));
        o.b(q == q2);
        o.b(q != q2);
        o.b(q == q);
        o.q(&Quaternion::default());
        o.q(&Quaternion::from_axis_angle(&v3, s));
        o.end();
    }
}

// ------------------------------------------------------------------ rect ---

fn gen_r(r: &mut Rng) -> Rect {
    match r.below(6) {
        0 => {
            let l = edge_f(r);
            let t = edge_f(r);
            let rr = edge_f(r);
            let b = edge_f(r);
            Rect::make_ltrb(l, t, rr, b)
        }
        1 => {
            let x = sane_f(r);
            let y = sane_f(r);
            let w = sane_f(r);
            let h = sane_f(r);
            Rect::make_xywh(x, y, w, h)
        }
        2 => {
            let l = r.below(11) as f32 - 5.0;
            let t = r.below(11) as f32 - 5.0;
            let rr = r.below(11) as f32 - 5.0;
            let b = r.below(11) as f32 - 5.0;
            Rect::make_ltrb(l, t, rr, b)
        }
        3 => Rect::make_maximum(),
        _ => {
            let l = sane_f(r);
            let t = sane_f(r);
            let w = (r.unit() * 100.0) as f32;
            let h = (r.unit() * 100.0) as f32;
            Rect::make_xywh(l, t, w, h)
        }
    }
}

fn gen_ir<T: RectNum>(r: &mut Rng, bits: u32) -> TRect<T> {
    let e = |r: &mut Rng| T::from_i128(edge_i(r, bits) as i128);
    match r.below(4) {
        0 => {
            let l = e(r);
            let t = e(r);
            let rr = e(r);
            let b = e(r);
            TRect::make_ltrb(l, t, rr, b)
        }
        1 => {
            let x = e(r);
            let y = e(r);
            let w = e(r);
            let h = e(r);
            TRect::make_xywh(x, y, w, h)
        }
        2 => {
            let s = |r: &mut Rng| T::from_i128(r.below(11) as i128 - 5);
            let l = s(r);
            let t = s(r);
            let rr = s(r);
            let b = s(r);
            TRect::make_ltrb(l, t, rr, b)
        }
        _ => TRect::make_maximum(),
    }
}

impl Out {
    fn r(&mut self, r: &Rect) {
        self.f(r.get_left());
        self.f(r.get_top());
        self.f(r.get_right());
        self.f(r.get_bottom());
    }
    fn ir<T: RectNum>(&mut self, r: &TRect<T>) {
        self.i(r.get_left().to_i128() as i64);
        self.i(r.get_top().to_i128() as i64);
        self.i(r.get_right().to_i128() as i64);
        self.i(r.get_bottom().to_i128() as i64);
    }
    fn opt_r(&mut self, r: Option<Rect>) {
        match r {
            Some(r) => self.r(&r),
            None => self.s("none"),
        }
    }
    fn opt_ir<T: RectNum>(&mut self, r: Option<TRect<T>>) {
        match r {
            Some(r) => self.ir(&r),
            None => self.s("none"),
        }
    }
}

fn no_nan(v: f32) -> f32 {
    if v.is_nan() { 0.0 } else { v }
}

fn int_rects<T: RectNum>(r: &mut Rng, o: &mut Out, bits: u32, tag: &str, fr: &Rect)
where
    f32: saturated::SaturatedCast<T>,
{
    let a: TRect<T> = gen_ir(r, bits);
    let b: TRect<T> = gen_ir(r, bits);
    let e = |r: &mut Rng| T::from_i128(edge_i(r, bits) as i128);
    let dx = e(r);
    let dy = e(r);
    let px = e(r);
    let py = e(r);
    let sc = e(r);
    let nr = Rect::make_ltrb(
        no_nan(fr.get_left()),
        no_nan(fr.get_top()),
        no_nan(fr.get_right()),
        no_nan(fr.get_bottom()),
    );
    o.tag(tag);
    o.ir(&a);
    o.ir(&b);
    for v in [dx, dy, px, py, sc] {
        o.i(v.to_i128() as i64);
    }
    o.r(&nr);
    o.arrow();
    o.b(a == b);
    o.b(a.is_empty());
    o.b(a.is_square());
    o.b(a.is_maximum());
    o.ip(a.get_origin());
    o.isz(a.get_size());
    o.i(a.get_x().to_i128() as i64);
    o.i(a.get_y().to_i128() as i64);
    o.i(a.get_width().to_i128() as i64);
    o.i(a.get_height().to_i128() as i64);
    o.ip(a.get_left_top());
    o.ip(a.get_right_top());
    o.ip(a.get_left_bottom());
    o.ip(a.get_right_bottom());
    o.i(a.area().to_i128() as i64);
    o.p(a.get_center());
    for v in a.get_xywh() {
        o.i(v.to_i128() as i64);
    }
    o.ir(&a.get_positive());
    for p in a.get_points() {
        o.ip(p);
    }
    o.ir(&a.scale(sc));
    o.ir(&a.scale_xy(dx, dy));
    o.ir(&a.scale_point(TPoint::new(dx, dy)));
    o.ir(&a.scale_size(TSize::new(dx, dy)));
    o.b(a.contains(&TPoint::new(px, py)));
    o.b(a.contains_inclusive(&TPoint::new(px, py)));
    o.b(a.contains_rect(&b));
    o.ir(&a.union(&b));
    o.opt_ir(a.intersection(&b));
    o.ir(&a.intersection_or_empty(&b));
    o.b(a.intersects_with_rect(&b));
    o.opt_ir(a.cutout(&b));
    o.ir(&a.cutout_or_empty(&b));
    o.ir(&a.shift(dx, dy));
    o.ir(&a.shift_point(TPoint::new(dx, dy)));
    o.ir(&a.expand_ltrb(dx, dy, px, py));
    o.ir(&a.expand(dx));
    o.ir(&a.expand_xy(dx, dy));
    o.ir(&a.expand_point(TPoint::new(dx, dy)));
    o.ir(&a.expand_size(TSize::new(px, py)));
    o.ir(&a.project(b));
    o.ir(&TRect::<T>::make_xywh(dx, dy, px, py));
    o.ir(&TRect::<T>::make_wh(dx, dy));
    o.ir(&TRect::<T>::make_origin_size(&TPoint::new(dx, dy), &TSize::new(px, py)));
    o.ir(&TRect::<T>::make_size(&TSize::new(px, py)));
    o.ir(&TRect::<T>::make_circle_bounds(&TPoint::new(dx, dy), sc));
    o.ir(&TRect::<T>::make_ellipse_bounds(&TPoint::new(dx, dy), &TSize::new(px, py)));
    o.ir(&TRect::<T>::make_ellipse_bounds_point(&TPoint::new(dx, dy), &TPoint::new(px, py)));
    o.ir(&TRect::<T>::make_maximum());
    o.ir(&TRect::<T>::default());
    o.ir(&TRect::<T>::round_out(&nr));
    o.ir(&TRect::<T>::round_in(&nr));
    o.ir(&TRect::<T>::round(&nr));
    o.m(&a.get_normalizing_transform());
    o.r(&Rect::make(&a));
    o.b(nr.contains_rect_of(&a));
    let mut pts = Vec::new();
    let n = r.below(6);
    for _ in 0..n {
        let x = e(r);
        let y = e(r);
        pts.push(TPoint::new(x, y));
    }
    o.opt_ir(TRect::<T>::make_point_bounds(&pts));
    o.end();
}

fn suite_rect(r: &mut Rng, o: &mut Out, cases: i32) {
    for _ in 0..cases {
        let a = gen_r(r);
        let b = gen_r(r);
        let dx = if r.chance(3) { edge_f(r) } else { sane_f(r) };
        let dy = if r.chance(3) { edge_f(r) } else { sane_f(r) };
        let px = if r.chance(3) { edge_f(r) } else { sane_f(r) };
        let py = if r.chance(3) { edge_f(r) } else { sane_f(r) };
        let sc = if r.chance(3) { edge_f(r) } else { sane_f(r) };
        let sz = edge_s(r);
        let isz = {
            let w = edge_i(r, 64);
            let h = edge_i(r, 64);
            ISize::new(w, h)
        };

        o.tag("rect");
        o.r(&a);
        o.r(&b);
        for v in [dx, dy, px, py, sc] {
            o.f(v);
        }
        o.sz(sz);
        o.isz(isz);
        o.arrow();
        o.b(a == b);
        o.b(a == a);
        o.b(a.is_finite());
        o.b(a.is_empty());
        o.b(a.is_square());
        o.b(a.is_maximum());
        o.p(a.get_origin());
        o.sz(a.get_size());
        o.f(a.get_x());
        o.f(a.get_y());
        o.f(a.get_width());
        o.f(a.get_height());
        o.p(a.get_left_top());
        o.p(a.get_right_top());
        o.p(a.get_left_bottom());
        o.p(a.get_right_bottom());
        o.f(a.area());
        o.p(a.get_center());
        for v in a.get_ltrb() {
            o.f(v);
        }
        for v in a.get_xywh() {
            o.f(v);
        }
        o.r(&a.get_positive());
        for p in a.get_points() {
            o.p(p);
        }
        o.r(&a.scale(sc));
        o.r(&a.scale_xy(dx, dy));
        o.r(&a.scale_point(Point::new(dx, dy)));
        o.r(&a.scale_size(Size::new(px, py)));
        o.b(a.contains(&Point::new(px, py)));
        o.b(a.contains_inclusive(&Point::new(px, py)));
        o.b(a.contains_rect(&b));
        o.r(&a.union(&b));
        o.opt_r(a.intersection(&b));
        o.r(&a.intersection_or_empty(&b));
        o.b(a.intersects_with_rect(&b));
        o.opt_r(a.cutout(&b));
        o.r(&a.cutout_or_empty(&b));
        o.r(&a.shift(dx, dy));
        o.r(&a.shift_point(Point::new(dx, dy)));
        o.r(&a.expand_ltrb(dx, dy, px, py));
        o.r(&a.expand(dx));
        o.r(&a.expand_xy(dx, dy));
        o.r(&a.expand_point(Point::new(dx, dy)));
        o.r(&a.expand_size(Size::new(px, py)));
        o.r(&a.project(b));
        o.r(&Rect::make_xywh(dx, dy, px, py));
        o.r(&Rect::make_wh(dx, dy));
        o.r(&Rect::make_origin_size(&Point::new(dx, dy), &Size::new(px, py)));
        o.r(&Rect::make_size(&sz));
        o.r(&Rect::make_size(&isz));
        o.r(&Rect::make_circle_bounds(&Point::new(dx, dy), sc));
        o.r(&Rect::make_ellipse_bounds(&Point::new(dx, dy), &Size::new(px, py)));
        o.r(&Rect::make_ellipse_bounds_point(&Point::new(dx, dy), &Point::new(px, py)));
        o.r(&Rect::make_maximum());
        o.r(&Rect::default());
        o.r(&Rect::round_out(&a));
        o.r(&Rect::round_in(&a));
        o.r(&Rect::round(&a));
        o.r(&Rect::make(&a));
        let oa = if r.chance(3) { None } else { Some(a) };
        let ob = if r.chance(3) { None } else { Some(b) };
        o.r(&Rect::union_opt_b(&a, ob));
        o.r(&Rect::union_opt_a(oa, &b));
        o.opt_r(Rect::union_opt(oa, ob));
        o.opt_r(Rect::intersection_opt_b(&a, ob));
        o.opt_r(Rect::intersection_opt_a(oa, &b));
        o.opt_r(Rect::intersection_opt(oa, ob));
        let mut pts = Vec::new();
        let n = r.below(6);
        for _ in 0..n {
            pts.push(if r.chance(4) { edge_p(r) } else { sane_p(r) });
        }
        o.opt_r(Rect::make_point_bounds(&pts));
        o.opt_r(Rect::make_point_bounds(&pts));
        o.end();

        let m = gen_m(r);
        let mw = if r.chance(4) { edge_f(r) } else { (r.unit() * 20.0) as f32 };
        let mh = if r.chance(4) { edge_f(r) } else { (r.unit() * 20.0) as f32 };
        o.tag("rect_xform");
        o.r(&a);
        o.m(&m);
        o.f(mw);
        o.f(mh);
        o.arrow();
        for p in a.get_transformed_points(&m) {
            o.p(p);
        }
        o.r(&a.transform_bounds(&m));
        o.r(&a.transform_and_clip_bounds(&m));
        o.m(&a.get_normalizing_transform());
        o.opt_r(a.expand_to_min_transformed_size(Size::new(mw, mh), &m));
        o.end();

        int_rects::<i64>(r, o, 64, "irect64", &a);
        int_rects::<i32>(r, o, 32, "irect32", &b);
    }
}

// ------------------------------------------------------------------ misc ---

fn suite_misc(r: &mut Rng, o: &mut Out, cases: i32) {
    for _ in 0..cases {
        let angle = if r.chance(3) { edge_f(r) } else { sane_f(r) };
        let tc = edge_d(r);
        let ts = edge_d(r);
        let v = if r.chance(3) { edge_p(r) } else { sane_p(r) };
        let rad = edge_d(r);
        let sz = edge_s(r);
        o.tag("trig");
        o.f(angle);
        o.d(tc);
        o.d(ts);
        o.p(v);
        o.d(rad);
        o.sz(sz);
        o.arrow();
        let t = Trig::from_radians(Radians::new(angle));
        o.d(t.cos);
        o.d(t.sin);
        o.p(t * v);
        o.p(t * rad);
        o.p(t * sz);
        let n = -t;
        o.d(n.cos);
        o.d(n.sin);
        let u = Trig::new(tc, ts);
        o.p(u * v);
        o.p(u * rad);
        o.p(u * sz);
        o.end();

        let sg = edge_f(r);
        o.tag("sigma");
        o.f(sg);
        o.arrow();
        o.f(Radius::from(Sigma::new(sg)).radius);
        o.f(Sigma::from(Radius::new(sg)).sigma);
        o.f(Sigma::default().sigma);
        o.f(Radius::default().radius);
        o.f(kKernelRadiusPerSigma);
        o.end();

        let d0 = if r.chance(3) { edge_p(r) } else { sane_p(r) };
        let d1 = if r.chance(3) { edge_p(r) } else { sane_p(r) };
        let mag = edge_f(r);
        o.tag("separated");
        o.p(d0);
        o.p(d1);
        o.f(mag);
        o.arrow();
        let s0 = SeparatedVector2::from_vector(d0);
        let s1 = SeparatedVector2::from_vector(d1);
        let s2 = SeparatedVector2::new(d0, mag);
        let s3 = SeparatedVector2::default();
        o.p(s0.direction);
        o.f(s0.magnitude);
        o.p(s0.get_vector());
        o.p(s0.get_direction());
        o.f(s0.get_alignment(&s1));
        o.f(s0.angle_to(&s1).radians);
        o.f(s0.cross(&s1));
        o.p(s2.get_vector());
        o.f(s2.get_alignment(&s0));
        o.p(s3.direction);
        o.f(s3.magnitude);
        o.end();

        let mut num = edge_i(r, 32) as i32;
        let mut den = edge_i(r, 32) as u32;
        let mut num2 =
            if r.chance(2) { num.wrapping_mul(r.below(5) as i32) } else { edge_i(r, 32) as i32 };
        let mut den2 =
            if r.chance(2) { den.wrapping_mul(r.below(5) as u32) } else { edge_i(r, 32) as u32 };
        if r.chance(4) {
            num = r.below(21) as i32 - 10;
            den = r.below(10) as u32;
            num2 = r.below(21) as i32 - 10;
            den2 = r.below(10) as u32;
        }
        let ra = Rational::new(num, den);
        let rb = Rational::new(num2, den2);
        o.tag("rational");
        o.i(num as i64);
        o.u(den as u64);
        o.i(num2 as i64);
        o.u(den2 as u64);
        o.arrow();
        o.i(ra.get_numerator() as i64);
        o.u(ra.get_denominator() as u64);
        o.b(ra == rb);
        o.b(ra.lt(&rb));
        o.b(rb.lt(&ra));
        o.u(ra.get_hash());
        o.f(ra.to_scalar());
        let inv = ra.invert();
        o.i(inv.get_numerator() as i64);
        o.u(inv.get_denominator() as u64);
        let one = Rational::from_int(num);
        o.u(one.get_denominator() as u64);
        o.end();

        let origin = if r.chance(3) { edge_p(r) } else { sane_p(r) };
        let scale = if r.chance(3) { edge_f(r) } else { sane_f(r) };
        let w = if r.chance(3) { edge_f(r) } else { sane_f(r) };
        let h = if r.chance(3) { edge_f(r) } else { sane_f(r) };
        let c0 = edge_f(r);
        let c1 = edge_f(r);
        o.tag("rstransform");
        o.p(origin);
        o.f(scale);
        o.f(angle);
        o.f(w);
        o.f(h);
        o.f(c0);
        o.f(c1);
        o.arrow();
        let rst = RSTransform::make(origin, scale, Radians::new(angle));
        o.f(rst.scaled_cos);
        o.f(rst.scaled_sin);
        o.f(rst.translate_x);
        o.f(rst.translate_y);
        o.b(rst.is_axis_aligned());
        o.m(&rst.get_matrix());
        for p in rst.get_quad(w, h) {
            o.p(p);
        }
        for p in rst.get_quad_size(Size::new(h, w)) {
            o.p(p);
        }
        o.opt_r(rst.get_bounds(w, h));
        o.opt_r(rst.get_bounds_size(Size::new(h, w)));
        let raw = RSTransform::new(c0, c1, w, h);
        o.b(raw.is_axis_aligned());
        o.m(&raw.get_matrix());
        o.opt_r(raw.get_bounds(scale, scale));
        let def = RSTransform::default();
        o.f(def.scaled_cos);
        o.f(def.scaled_sin);
        o.end();

        let p0 = if r.chance(4) { edge_p(r) } else { sane_p(r) };
        let p1 = if r.chance(4) { edge_p(r) } else { sane_p(r) };
        let p2 = if r.chance(4) { edge_p(r) } else { sane_p(r) };
        let p3 = if r.chance(4) { edge_p(r) } else { sane_p(r) };
        let sf = if r.chance(4) { edge_f(r) } else { (r.unit() * 4.0) as f32 };
        let cw = if r.chance(4) { edge_f(r) } else { (r.unit() * 2.0) as f32 };
        o.tag("wangs");
        o.p(p0);
        o.p(p1);
        o.p(p2);
        o.p(p3);
        o.f(sf);
        o.f(cw);
        o.arrow();
        o.f(compute_cubic_subdivisions(sf, p0, p1, p2, p3));
        o.f(compute_quadradic_subdivisions(sf, p0, p1, p2));
        o.f(compute_conic_subdivisions(sf, p0, p1, p2, cw));
        o.end();

        let nc = 2 + r.below(7) as usize;
        let mut colors = Vec::new();
        let mut stops: Vec<f32> = Vec::new();
        for _ in 0..nc {
            colors.push(comp_c(r));
        }
        if nc == 2 && r.chance(2) {
            let s0 = edge_f(r);
            let s1 = edge_f(r);
            stops = vec![s0, s1];
        } else {
            stops.push(0.0);
            for _ in 1..nc - 1 {
                let prev = *stops.last().unwrap();
                let step = match r.below(4) {
                    0 => 0.0,
                    1 => (r.unit() * 1e-3) as f32,
                    _ => (r.unit() * (1.0 - prev as f64) * 0.5) as f32,
                };
                stops.push(cxx::min(1.0, prev + step));
            }
            stops.push(1.0);
        }
        o.tag("gradient");
        for i in 0..colors.len() {
            o.c(colors[i]);
            o.f(stops[i]);
        }
        o.arrow();
        let g = create_gradient_buffer(&colors, &stops);
        o.u(g.colors.len() as u64);
        for col in &g.colors {
            o.c(*col);
        }
        o.end();

        let sp = StrokeParameters::default();
        let sq = StrokeParameters { width: w, cap: Cap::kRound, join: Join::kBevel, miter_limit: h };
        o.tag("stroke");
        o.f(sp.width);
        o.i(sp.cap as i64);
        o.i(sp.join as i64);
        o.f(sp.miter_limit);
        o.b(sp == sq);
        o.b(sq == sq);
        o.end();
    }
}

// ----------------------------------------------- round shapes and paths ---

struct PrintReceiver<'a> {
    o: &'a mut Out,
    accept_conics: bool,
}

impl PathReceiver for PrintReceiver<'_> {
    fn move_to(&mut self, p2: &Point, will_be_closed: bool) {
        self.o.s("M");
        self.o.p(*p2);
        self.o.b(will_be_closed);
    }
    fn line_to(&mut self, p2: &Point) {
        self.o.s("L");
        self.o.p(*p2);
    }
    fn quad_to(&mut self, cp: &Point, p2: &Point) {
        self.o.s("Q");
        self.o.p(*cp);
        self.o.p(*p2);
    }
    fn conic_to(&mut self, cp: &Point, p2: &Point, weight: Scalar) -> bool {
        self.o.s("K");
        self.o.p(*cp);
        self.o.p(*p2);
        self.o.f(weight);
        self.accept_conics
    }
    fn cubic_to(&mut self, cp1: &Point, cp2: &Point, p2: &Point) {
        self.o.s("C");
        self.o.p(*cp1);
        self.o.p(*cp2);
        self.o.p(*p2);
    }
    fn close(&mut self) {
        self.o.s("Z");
    }
}

struct DefaultConicReceiver<'a> {
    o: &'a mut Out,
}

impl PathReceiver for DefaultConicReceiver<'_> {
    fn move_to(&mut self, _p2: &Point, _will_be_closed: bool) {
        self.o.s("m");
    }
    fn line_to(&mut self, _p2: &Point) {
        self.o.s("l");
    }
    fn quad_to(&mut self, _cp: &Point, _p2: &Point) {
        self.o.s("q");
    }
    fn cubic_to(&mut self, _cp1: &Point, _cp2: &Point, _p2: &Point) {
        self.o.s("c");
    }
    fn close(&mut self) {
        self.o.s("z");
    }
}

impl Out {
    fn rr(&mut self, rr: &RoundingRadii) {
        self.sz(rr.top_left);
        self.sz(rr.top_right);
        self.sz(rr.bottom_left);
        self.sz(rr.bottom_right);
    }
    fn source(&mut self, source: &dyn PathSource, accept_conics: bool) {
        self.s("[");
        self.i(source.get_fill_type() as i64);
        self.r(&source.get_bounds());
        self.b(source.is_convex());
        let mut receiver = PrintReceiver { o: self, accept_conics };
        source.dispatch(&mut receiver);
        self.s("]");
    }
}

fn radius_f(r: &mut Rng) -> f32 {
    match r.below(8) {
        0 => 0.0,
        1 => edge_f(r),
        2 => -(r.unit() * 10.0) as f32,
        _ => (r.unit() * 60.0) as f32,
    }
}
fn radius_s(r: &mut Rng) -> Size {
    let w = radius_f(r);
    let h = if r.chance(3) { w } else { radius_f(r) };
    Size::new(w, h)
}
fn unit_s(r: &mut Rng, scale: f64) -> Size {
    let w = (r.unit() * scale) as f32;
    let h = (r.unit() * scale) as f32;
    Size::new(w, h)
}
fn gen_radii(r: &mut Rng) -> RoundingRadii {
    match r.below(4) {
        0 => RoundingRadii::make_radius(radius_f(r)),
        1 => RoundingRadii::make_radii(radius_s(r)),
        _ => {
            let tl = radius_s(r);
            let tr = radius_s(r);
            let bl = radius_s(r);
            let br = radius_s(r);
            RoundingRadii { top_left: tl, top_right: tr, bottom_left: bl, bottom_right: br }
        }
    }
}
fn round_bounds(r: &mut Rng) -> Rect {
    if r.chance(6) {
        return gen_r(r);
    }
    let l = sane_f(r);
    let t = sane_f(r);
    let mut w = (r.unit() * 200.0) as f32;
    let h = if r.chance(4) { w } else { (r.unit() * 200.0) as f32 };
    if r.chance(8) {
        w = -w;
    }
    Rect::make_xywh(l, t, w, h)
}
fn near_point(r: &mut Rng, b: &Rect) -> Point {
    if r.chance(8) {
        return edge_p(r);
    }
    let mut fx = (r.unit() * 1.2 - 0.1) as f32;
    let fy = (r.unit() * 1.2 - 0.1) as f32;
    if r.chance(8) {
        fx = (fx * 4.0).round() / 4.0;
    }
    Point::new(b.get_left() + fx * b.get_width(), b.get_top() + fy * b.get_height())
}

fn suite_round(r: &mut Rng, o: &mut Out, cases: i32) {
    for _ in 0..cases {
        let bounds = round_bounds(r);
        let radii = gen_radii(r);
        let tol = if r.chance(2) { kEhCloseEnough } else { sane_f(r) };
        let sc = sane_f(r);
        o.tag("radii");
        o.r(&bounds);
        o.rr(&radii);
        o.f(tol);
        o.f(sc);
        o.arrow();
        o.b(radii.is_finite());
        o.b(radii.are_all_corners_empty());
        o.b(radii.are_all_corners_same());
        o.b(radii.are_all_corners_same_tol(tol));
        o.b(radii.are_all_corners_circular());
        o.rr(&radii.scaled(&bounds));
        o.rr(&(radii * sc));
        o.b(radii == radii.scaled(&bounds));
        o.rr(&RoundingRadii::make_nine_patch(sc, tol, bounds.get_left(), bounds.get_top()));
        o.end();

        let rad = radius_f(r);
        let rx = radius_f(r);
        let ry = radius_f(r);
        let dx = sane_f(r);
        let dy = sane_f(r);
        let dz = sane_f(r);
        let dw = sane_f(r);
        let rr = RoundRect::make_rect_radii(&bounds, &radii);
        o.tag("round_rect");
        o.r(&bounds);
        o.rr(&radii);
        o.f(rad);
        o.f(rx);
        o.f(ry);
        o.arrow();
        o.r(rr.get_bounds());
        o.rr(rr.get_radii());
        o.b(rr.is_finite());
        o.b(rr.is_empty());
        o.b(rr.is_rect());
        o.b(rr.is_oval());
        for _ in 0..6 {
            let p = near_point(r, rr.get_bounds());
            o.p(p);
            o.b(rr.contains(&p));
        }
        let variants = [
            RoundRect::make_rect(&bounds),
            RoundRect::make_oval(&bounds),
            RoundRect::make_rect_radius(&bounds, rad),
            RoundRect::make_rect_xy(&bounds, rx, ry),
            RoundRect::make_rect_xy_size(&bounds, Size::new(ry, rx)),
            RoundRect::make_nine_patch(&bounds, rx, ry, rad, dx),
            rr.shift(dx, dy),
            rr.expand_ltrb(dx, dy, dz, dw),
            rr.expand_xy(dx, dy),
            rr.expand(dz),
        ];
        for v in &variants {
            o.r(v.get_bounds());
            o.rr(v.get_radii());
            o.b(v.is_rect());
            o.b(v.is_oval());
            o.b(*v == rr);
        }
        let inner = RoundRect::make_rect_radii(&bounds.expand(-5.0), &radii);
        o.source(&RoundRectPathSource::new(&rr), true);
        let accept = r.chance(2);
        o.source(&DiffRoundRectPathSource::new(&rr, &inner), accept);
        o.end();

        let rse = RoundSuperellipse::make_rect_radii(&bounds, &radii);
        o.tag("rse");
        o.r(&bounds);
        o.rr(&radii);
        o.arrow();
        o.r(rse.get_bounds());
        o.rr(rse.get_radii());
        o.b(rse.is_finite());
        o.b(rse.is_empty());
        o.b(rse.is_rect());
        o.b(rse.is_oval());
        for _ in 0..6 {
            let p = near_point(r, rse.get_bounds());
            o.p(p);
            o.b(rse.contains(&p));
        }
        let rvariants = [
            RoundSuperellipse::make_rect(&bounds),
            RoundSuperellipse::make_oval(&bounds),
            RoundSuperellipse::make_rect_radius(&bounds, rad),
            RoundSuperellipse::make_rect_xy(&bounds, rx, ry),
            RoundSuperellipse::make_rect_xy_size(&bounds, Size::new(ry, rx)),
            rse.shift(dx, dy),
            rse.expand_ltrb(dx, dy, dz, dw),
            rse.expand_xy(dx, dy),
            rse.expand(dz),
        ];
        for v in &rvariants {
            o.r(v.get_bounds());
            o.rr(v.get_radii());
            o.b(v.is_rect());
            o.b(v.is_oval());
            o.b(*v == rse);
        }
        let approx = rse.to_approximate_round_rect();
        o.r(approx.get_bounds());
        o.rr(approx.get_radii());
        o.source(&RoundSuperellipsePathSource::new(&rse), true);
        o.end();

        {
            let l = sane_f(r);
            let t = sane_f(r);
            let w = (r.unit() * 300.0) as f32;
            let h = (r.unit() * 300.0) as f32;
            let pb = Rect::make_xywh(l, t, w, h);
            let mut pr = (r.unit() * 200.0) as f32;
            if r.chance(8) {
                pr = 0.0;
            }
            if r.chance(8) {
                pr = (r.unit() * 2e-3) as f32;
            }
            let tl = unit_s(r, 150.0);
            let tr = unit_s(r, 150.0);
            let bl = unit_s(r, 150.0);
            let br = unit_s(r, 150.0);
            let mut pradii =
                RoundingRadii { top_left: tl, top_right: tr, bottom_left: bl, bottom_right: br };
            if r.chance(4) {
                pradii = RoundingRadii::make_radius(pr);
            }
            o.tag("rse_param");
            o.r(&pb);
            o.f(pr);
            o.rr(&pradii);
            o.arrow();
            for param in [
                RoundSuperellipseParam::make_bounds_radius(&pb, pr),
                RoundSuperellipseParam::make_bounds_radii(&pb, &pradii),
            ] {
                for q in [&param.top_right, &param.bottom_right, &param.bottom_left, &param.top_left] {
                    o.p(q.offset);
                    o.p(q.signed_scale);
                    for oc in [&q.top, &q.right] {
                        o.p(oc.offset);
                        o.f(oc.se_a);
                        o.f(oc.se_n);
                        o.f(oc.se_max_theta);
                        o.p(oc.circle_start);
                        o.p(oc.circle_center);
                        o.f(oc.circle_max_angle.radians);
                        o.f(oc.circle_radius);
                    }
                }
                o.b(param.all_corners_same);
                o.f(param.top_split);
                o.f(param.bottom_split);
                o.f(param.left_split);
                o.f(param.right_split);
                for _ in 0..4 {
                    let p = near_point(r, &pb);
                    o.p(p);
                    o.b(param.contains(&p));
                }
                let mut receiver = PrintReceiver { o: &mut *o, accept_conics: true };
                param.dispatch(&mut receiver);
            }
            o.end();
        }

        let mut start = if r.chance(4) { edge_f(r) } else { (r.unit() * 1440.0 - 720.0) as f32 };
        let mut sweep = if r.chance(4) { edge_f(r) } else { (r.unit() * 1440.0 - 720.0) as f32 };
        if r.chance(4) {
            start = (r.below(9) as i32 * 90 - 360) as f32;
            sweep = (r.below(9) as i32 * 90 - 360) as f32;
        }
        let include_center = r.chance(2);
        let step_count = r.below(40) as usize;
        let ab = if r.chance(5) { gen_r(r) } else { round_bounds(r) };
        let arc = Arc::new(&ab, Degrees::new(start), Degrees::new(sweep), include_center);
        o.tag("arc");
        o.r(&ab);
        o.f(start);
        o.f(sweep);
        o.b(include_center);
        o.u(step_count as u64);
        o.arrow();
        o.r(arc.get_oval_bounds());
        o.p(arc.get_oval_center());
        o.sz(arc.get_oval_size());
        o.f(arc.get_start().degrees);
        o.f(arc.get_sweep().degrees);
        o.b(arc.include_center());
        o.b(arc.is_perfect_circle());
        o.b(arc.is_full_circle());
        o.r(&arc.get_tight_arc_bounds());
        for simplify in [true, false] {
            let it = arc.compute_iterations(step_count, simplify);
            o.p(it.start);
            o.p(it.end);
            o.u(it.quadrant_count as u64);
            for i in 0..it.quadrant_count {
                o.p(it.quadrants[i].axis);
                o.u(it.quadrants[i].start_index as u64);
                o.u(it.quadrants[i].end_index as u64);
            }
            o.u(it.get_point_count() as u64);
        }
        o.end();

        let sb = gen_r(r);
        let p0 = if r.chance(4) { edge_p(r) } else { sane_p(r) };
        let p1 = if r.chance(4) { edge_p(r) } else { sane_p(r) };
        let on = if r.chance(4) { edge_f(r) } else { (r.unit() * 40.0) as f32 };
        let mut off = if r.chance(4) { edge_f(r) } else { (r.unit() * 40.0) as f32 };
        {
            let length = p0.get_distance(&p1);
            if length > 0.0
                && on >= 0.0
                && off > 0.0
                && on.is_finite()
                && off.is_finite()
                && (on + off) * 2000.0 < length
            {
                off = length / 1000.0;
            }
        }
        let m = gen_m(r);
        o.tag("paths");
        o.r(&sb);
        o.p(p0);
        o.p(p1);
        o.f(on);
        o.f(off);
        o.m(&m);
        o.arrow();
        o.source(&RectPathSource::new(&sb), true);
        o.source(&EllipsePathSource::new(&sb), true);
        o.source(&DashedLinePathSource::new(p0, p1, on, off), true);
        {
            let accept = r.chance(2);
            let mut inner = PrintReceiver { o: &mut *o, accept_conics: accept };
            let mut transformer = PathTransformer::new(&mut inner, &m);
            EllipsePathSource::new(&sb).dispatch(&mut transformer);
            RoundRectPathSource::new(&rr).dispatch(&mut transformer);
            transformer.quad_to(&p0, &p1);
            transformer.cubic_to(&p1, &p0, &p1);
            drop(transformer);
            inner.o.s("ret");
            let ret = PathTransformer::new(&mut inner, &m).conic_to(&p0, &p1, on);
            inner.o.b(ret);
        }
        {
            let mut def = DefaultConicReceiver { o: &mut *o };
            let ret = def.conic_to(&p0, &p1, on);
            def.o.b(ret);
            EllipsePathSource::new(&sb).dispatch(&mut def);
        }
        o.end();
    }
}

// ------------------------------------------------------------- benchmarks ---
//
// geometry_dump bench <name> <rounds>: see oracle/geometry_dump.cc's Bench,
// which this mirrors; the checksums must agree.

struct Fold(u64);

impl Fold {
    #[inline(always)]
    fn f(&mut self, v: f32) {
        let b = if v.is_nan() { 0x7fc00000u32 } else { v.to_bits() };
        self.0 = (self.0 ^ b as u64).wrapping_mul(0x100000001b3);
    }
    #[inline(always)]
    fn u(&mut self, v: u64) {
        self.0 = (self.0 ^ v).wrapping_mul(0x100000001b3);
    }
}

struct CountingReceiver<'a>(&'a mut Fold);

impl PathReceiver for CountingReceiver<'_> {
    fn move_to(&mut self, p2: &Point, _: bool) {
        self.0.f(p2.x);
    }
    fn line_to(&mut self, p2: &Point) {
        self.0.f(p2.y);
    }
    fn quad_to(&mut self, cp: &Point, p2: &Point) {
        self.0.f(cp.x + p2.y);
    }
    fn conic_to(&mut self, cp: &Point, p2: &Point, w: Scalar) -> bool {
        self.0.f(cp.x + p2.y + w);
        true
    }
    fn cubic_to(&mut self, a: &Point, b: &Point, c: &Point) {
        self.0.f(a.x + b.y + c.x);
    }
    fn close(&mut self) {
        self.0.u(1);
    }
}

fn peak_rss_kb() -> i64 {
    let status = std::fs::read_to_string("/proc/self/status").unwrap_or_default();
    for l in status.lines() {
        if let Some(v) = l.strip_prefix("VmHWM:") {
            return v.trim().trim_end_matches("kB").trim().parse().unwrap_or(-1);
        }
    }
    -1
}

#[allow(non_upper_case_globals)]
const kN: usize = 4096;

fn bench(name: &str, rounds: i32) {
    let mut r = Rng { s: 42 };
    let mut p0 = vec![Point::default(); kN];
    let mut p1 = vec![Point::default(); kN];
    let mut p2 = vec![Point::default(); kN];
    let mut s = vec![0.0f32; kN];
    let mut m0 = vec![Matrix::default(); kN];
    let mut m1 = vec![Matrix::default(); kN];
    let mut r0 = vec![Rect::default(); kN];
    let mut r1 = vec![Rect::default(); kN];
    let mut i0 = vec![IRect::default(); kN];
    let mut i1 = vec![IRect::default(); kN];
    let mut c0 = vec![Color::default(); kN];
    let mut c1 = vec![Color::default(); kN];
    let mut rr = vec![RoundingRadii::default(); kN];
    for i in 0..kN {
        p0[i] = sane_p(&mut r);
        p1[i] = sane_p(&mut r);
        p2[i] = sane_p(&mut r);
        s[i] = sane_f(&mut r);
        m0[i] = gen_m(&mut r);
        m1[i] = gen_m(&mut r);
        r0[i] = round_bounds(&mut r);
        r1[i] = round_bounds(&mut r);
        i0[i] = gen_ir(&mut r, 64);
        i1[i] = gen_ir(&mut r, 64);
        c0[i] = unit_c(&mut r);
        c1[i] = unit_c(&mut r);
        rr[i] = gen_radii(&mut r);
    }
    // Fixed-length arrays, so that indexing with `i < kN` needs no bounds
    // check (the C++ loop indexes std::vector unchecked).
    fn fixed<T>(v: Vec<T>) -> Box<[T; kN]> {
        v.into_boxed_slice().try_into().unwrap_or_else(|_| unreachable!())
    }
    let (p0, p1, p2, s) = (fixed(p0), fixed(p1), fixed(p2), fixed(s));
    let (m0, m1, r0, r1) = (fixed(m0), fixed(m1), fixed(r0), fixed(r1));
    let (i0, i1, c0, c1, rr) = (fixed(i0), fixed(i1), fixed(c0), fixed(c1), fixed(rr));
    let mut sum = Fold(0);
    let mut times: Vec<f64> = Vec::new();
    for _ in 0..rounds {
        let t0 = std::time::Instant::now();
        let o = &mut sum;
        match name {
            "point" => {
                for i in 0..kN {
                    o.f(p0[i].get_distance_to_segment(p1[i], p2[i]));
                    o.f(p0[i].normalize().x);
                    o.f(p0[i].rotate(&Radians::new(s[i])).y);
                    o.f((p0[i] * p1[i] + p2[i] / s[i]).x);
                    o.f(p0[i].angle_to(&p1[i]).radians);
                    o.f(p0[i].lerp(&p2[i], s[i]).y);
                }
            }
            "matrix" => {
                for i in 0..kN {
                    let m = m0[i] * m1[i];
                    let inv = m.invert();
                    o.f(inv.m[i & 15]);
                    o.f(m.get_determinant());
                    o.f((m * p0[i]).x);
                    o.f(m.get_max_basis_length_xy());
                    o.f(m.get_min_scale_2d().unwrap_or(-1.0));
                    o.f(Matrix::make_rotation_z(Radians::new(s[i])).m[1]);
                }
            }
            "decompose" => {
                for i in 0..kN {
                    if let Some(d) = m0[i].decompose() {
                        o.f(d.scale.x);
                        o.f(Matrix::from_decomposition(&d).m[i & 15]);
                    }
                }
            }
            "rect" => {
                for i in 0..kN {
                    o.f(r0[i].union(&r1[i]).get_left());
                    o.f(r0[i].intersection_or_empty(&r1[i]).get_right());
                    o.u(r0[i].contains(&p0[i]) as u64);
                    o.u(r0[i].contains_rect(&r1[i]) as u64);
                    o.f(r0[i].transform_bounds(&m0[i]).get_top());
                    o.f(r0[i].transform_and_clip_bounds(&m1[i]).get_bottom());
                    let nr = Rect::make_ltrb(
                        no_nan(r0[i].get_left()),
                        no_nan(r0[i].get_top()),
                        no_nan(r0[i].get_right()),
                        no_nan(r0[i].get_bottom()),
                    );
                    o.u(IRect::round_out(&nr).get_width() as u64);
                    o.f(r0[i].expand(s[i]).get_width());
                    o.f(r0[i].get_normalizing_transform().m[12]);
                    o.f(r0[i].project(r1[i]).get_left());
                }
            }
            "irect" => {
                for i in 0..kN {
                    o.u(i0[i].union(&i1[i]).get_left() as u64);
                    o.u(i0[i].intersection_or_empty(&i1[i]).get_right() as u64);
                    o.u(i0[i].expand(i1[i].get_left()).get_width() as u64);
                    o.u(i0[i].shift(i1[i].get_top(), i1[i].get_right()).get_bottom() as u64);
                    o.u(i0[i].area() as u64);
                    o.f(i0[i].get_center().x);
                }
            }
            "color" => {
                for i in 0..kN {
                    // An exclusive range, as the C++ loop is `m <= kLastMode` on
                    // an int: `0..=n` carries an exhaustion flag.
                    for mode in 0..BlendMode::kLastMode as u8 + 1 {
                        o.f(c0[i].blend(c1[i], BlendMode::from_u8(mode).unwrap()).red);
                    }
                    o.f(c0[i].linear_to_srgb().green);
                    o.f(c0[i].srgb_to_linear().blue);
                    o.u(Color::to_i_color(c0[i]) as u64);
                }
            }
            "rrect" => {
                for i in 0..kN {
                    let rrect = RoundRect::make_rect_radii(&r0[i], &rr[i]);
                    o.u(rrect.contains(&p0[i]) as u64);
                    o.u(rrect.contains(&rrect.get_bounds().get_center()) as u64);
                    RoundRectPathSource::new(&rrect).dispatch(&mut CountingReceiver(o));
                }
            }
            "rse" => {
                for i in 0..kN {
                    let rse = RoundSuperellipse::make_rect_radii(&r0[i], &rr[i]);
                    o.u(rse.contains(&p0[i]) as u64);
                    o.u(rse.contains(&rse.get_bounds().get_center()) as u64);
                    RoundSuperellipsePathSource::new(&rse).dispatch(&mut CountingReceiver(o));
                }
            }
            "arc" => {
                for i in 0..kN {
                    let arc = Arc::new(
                        &r0[i],
                        Degrees::new(s[i] * 3.0),
                        Degrees::new(s[(i + 1) % kN] * 4.0),
                        (i & 1) != 0,
                    );
                    o.f(arc.get_tight_arc_bounds().get_left());
                    let it = arc.compute_iterations(18, true);
                    o.u(it.quadrant_count as u64);
                    o.u(it.get_point_count() as u64);
                }
            }
            "gradient" => {
                for i in 0..kN / 16 {
                    let colors = [c0[i], c1[i], c0[i + 1], c1[i + 1]];
                    let a = s[i].abs() / 400.0;
                    let b = s[i + 1].abs() / 400.0;
                    let stops = [0.0, cxx::min(a, b), cxx::max(a, b), 1.0];
                    let g = create_gradient_buffer(&colors, &stops);
                    o.u(g.colors.len() as u64);
                    o.f(g.colors.last().unwrap().red);
                }
            }
            _ => {
                eprintln!("unknown bench {name}");
                std::process::exit(2);
            }
        }
        times.push(t0.elapsed().as_nanos() as f64);
    }
    times.sort_by(|a, b| a.partial_cmp(b).unwrap());
    println!(
        "{name} fastest_ns {:.0} median_ns {:.0} slowest_ns {:.0} checksum {:016x} peak_rss_kb {} p90_ns {:.0}",
        times[0],
        times[times.len() / 2],
        times[times.len() - 1],
        sum.0,
        peak_rss_kb(),
        times[times.len() * 9 / 10]
    );
}

// ----------------------------------------------------------------- main ----

type Suite = fn(&mut Rng, &mut Out, i32);
const SUITES: &[(&str, Suite)] =
    &[
        ("scalar", suite_scalar),
        ("point", suite_point),
        ("size", suite_size),
        ("vector", suite_vector),
        ("color", suite_color),
        ("matrix", suite_matrix),
        ("rect", suite_rect),
        ("misc", suite_misc),
        ("round", suite_round),
    ];

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 4 {
        eprintln!("usage: geometry_dump <suite> <seed> <cases> | bench <suite> <rounds>");
        std::process::exit(2);
    }
    let mut o = Out { line: String::new(), sink: std::io::BufWriter::new(std::io::stdout()), discard: false };
    if args[1] == "bench" {
        bench(&args[2], args[3].parse().unwrap());
        return;
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
