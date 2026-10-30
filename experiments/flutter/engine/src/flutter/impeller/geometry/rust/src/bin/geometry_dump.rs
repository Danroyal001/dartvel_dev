// Not an upstream file: the port's side of the oracle (see
// oracle/geometry_dump.cc, which this mirrors suite by suite and line by line).
//
//   geometry_dump <suite> <seed> <cases>
//   geometry_dump bench <suite> <rounds>

#![allow(non_snake_case)]

use std::io::Write;

use impeller_geometry::constants::*;
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

// ----------------------------------------------------------------- main ----

type Suite = fn(&mut Rng, &mut Out, i32);
const SUITES: &[(&str, Suite)] =
    &[("scalar", suite_scalar), ("point", suite_point), ("size", suite_size)];

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
