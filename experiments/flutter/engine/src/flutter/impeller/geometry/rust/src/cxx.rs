// Not an upstream file: the C++ semantics the ported headers rely on.
//
// `std::min`, `std::max` and `std::clamp` (which differ from Rust's on NaN
// and on signed zeros), glibc's `lround`, and `Num`, which carries C++'s
// arithmetic conversions for the numeric types the geometry templates are
// instantiated with (float, double and the integer widths), so that a
// `TPoint<int64_t>` times a `float` computes in `float` and converts back as
// upstream's `static_cast<Type>(x * scale)` does.
//
// Signed overflow, undefined upstream, wraps (as the engine's targets do and
// as the oracle pins with -fwrapv). A float converted to an integer type out
// of its range is undefined upstream and saturates here.

use std::fmt::Debug;

/// `std::min(a, b)`: `(b < a) ? b : a`.
#[inline(always)]
pub fn min<T: PartialOrd>(a: T, b: T) -> T {
    if b < a { b } else { a }
}

/// `std::max(a, b)`: `(a < b) ? b : a`.
#[inline(always)]
pub fn max<T: PartialOrd>(a: T, b: T) -> T {
    if a < b { b } else { a }
}

/// `std::clamp(v, lo, hi)`: `v < lo ? lo : hi < v ? hi : v`.
#[inline(always)]
pub fn clamp<T: PartialOrd>(v: T, lo: T, hi: T) -> T {
    if v < lo {
        lo
    } else if hi < v {
        hi
    } else {
        v
    }
}

/// glibc's `lroundf`: round half away from zero; NaN and values outside
/// `long` give `LONG_MIN` (the conversion instruction's "integer
/// indefinite").
#[inline]
pub fn lround(x: f32) -> i64 {
    let r = x.round_c();
    if r.is_nan() || r >= 9.223372e18_f32 || r < -9.223372e18_f32 { i64::MIN } else { r as i64 }
}

/// The kinds of arithmetic types the templates are instantiated with.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Kind {
    I8,
    I16,
    I32,
    I64,
    U8,
    U16,
    U32,
    U64,
    F32,
    F64,
}

impl Kind {
    pub const fn is_float(self) -> bool {
        matches!(self, Kind::F32 | Kind::F64)
    }
    const fn is_signed(self) -> bool {
        matches!(self, Kind::I8 | Kind::I16 | Kind::I32 | Kind::I64)
    }
    const fn bits(self) -> u32 {
        match self {
            Kind::I8 | Kind::U8 => 8,
            Kind::I16 | Kind::U16 => 16,
            Kind::I32 | Kind::U32 | Kind::F32 => 32,
            Kind::I64 | Kind::U64 | Kind::F64 => 64,
        }
    }
    /// Integral promotion: types narrower than `int` become `int`.
    const fn promoted(self) -> Kind {
        match self {
            Kind::I8 | Kind::I16 | Kind::U8 | Kind::U16 => Kind::I32,
            k => k,
        }
    }
    /// The usual arithmetic conversions of C++ ([expr.arith.conv]).
    pub const fn common(a: Kind, b: Kind) -> Kind {
        if matches!(a, Kind::F64) || matches!(b, Kind::F64) {
            return Kind::F64;
        }
        if matches!(a, Kind::F32) || matches!(b, Kind::F32) {
            return Kind::F32;
        }
        let (a, b) = (a.promoted(), b.promoted());
        if a.is_signed() == b.is_signed() {
            return if a.bits() >= b.bits() { a } else { b };
        }
        let (s, u) = if a.is_signed() { (a, b) } else { (b, a) };
        if u.bits() >= s.bits() {
            u
        } else {
            s
        }
    }
    /// Wraps an integer value to this (integral) kind's width and sign.
    #[inline(always)]
    pub const fn wrap(self, v: i128) -> i128 {
        match self {
            Kind::I8 => v as i8 as i128,
            Kind::I16 => v as i16 as i128,
            Kind::I32 => v as i32 as i128,
            Kind::I64 => v as i64 as i128,
            Kind::U8 => v as u8 as i128,
            Kind::U16 => v as u16 as i128,
            Kind::U32 => v as u32 as i128,
            Kind::U64 => v as u64 as i128,
            Kind::F32 | Kind::F64 => v,
        }
    }
}

/// An arithmetic operator, for `Num::op`.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Op {
    Add,
    Sub,
    Mul,
    Div,
}

/// A C++ arithmetic type.
pub trait Num: Copy + PartialOrd + Default + Debug + 'static {
    const KIND: Kind;
    /// `std::numeric_limits<T>::lowest()` and `max()`.
    const LOWEST: Self;
    const MAX: Self;
    /// `static_cast<double>(self)`, `static_cast<float>(self)`.
    fn to_f64(self) -> f64;
    fn to_f32(self) -> f32;
    /// The integer value (integral kinds only).
    fn to_i128(self) -> i128;
    /// `static_cast<T>` from double, float and (wrapped) integers.
    fn from_f64(v: f64) -> Self;
    fn from_f32(v: f32) -> Self;
    fn from_i128(v: i128) -> Self;
    /// `T{0}`.
    fn zero() -> Self {
        Self::default()
    }

    /// `static_cast<Self>(self <op> u)`, computed in the common type of the
    /// two operands as C++ does.
    #[inline(always)]
    fn op<U: Num>(self, op: Op, u: U) -> Self {
        match Kind::common(Self::KIND, U::KIND) {
            Kind::F64 => {
                let (a, b) = (self.to_f64(), u.to_f64());
                Self::from_f64(match op {
                    Op::Add => a + b,
                    Op::Sub => a - b,
                    Op::Mul => a * b,
                    Op::Div => a / b,
                })
            }
            Kind::F32 => {
                let (a, b) = (self.to_f32(), u.to_f32());
                Self::from_f32(match op {
                    Op::Add => a + b,
                    Op::Sub => a - b,
                    Op::Mul => a * b,
                    Op::Div => a / b,
                })
            }
            k => {
                let (a, b) = (k.wrap(self.to_i128()), k.wrap(u.to_i128()));
                let r = match op {
                    Op::Add => a.wrapping_add(b),
                    Op::Sub => a.wrapping_sub(b),
                    Op::Mul => a.wrapping_mul(b),
                    // Division by zero traps upstream; it panics here.
                    Op::Div => a.wrapping_div(b),
                };
                Self::from_i128(k.wrap(r))
            }
        }
    }
    /// The same-type operators.
    #[inline(always)]
    fn add(self, o: Self) -> Self {
        self.op(Op::Add, o)
    }
    #[inline(always)]
    fn sub(self, o: Self) -> Self {
        self.op(Op::Sub, o)
    }
    #[inline(always)]
    fn mul(self, o: Self) -> Self {
        self.op(Op::Mul, o)
    }
    #[inline(always)]
    fn div(self, o: Self) -> Self {
        self.op(Op::Div, o)
    }
    /// Unary minus (after integral promotion, converted back).
    #[inline(always)]
    fn neg(self) -> Self {
        Self::zero().sub(self).neg_fix(self)
    }
    #[doc(hidden)]
    fn neg_fix(self, original: Self) -> Self;
    /// `std::floor`, `std::ceil`, `std::round` and `std::fabs` of a float, in
    /// its own type (an integer is returned unchanged: upstream only
    /// instantiates these on floats). The rounding ones are computed inline
    /// (see `impl_num_float!`), not by calling libm.
    fn floor_c(self) -> Self;
    fn ceil_c(self) -> Self;
    fn round_c(self) -> Self;
    fn fabs(self) -> Self;
    /// `std::sqrt` of the value: `sqrtf` for float, `sqrt` for double, and
    /// `sqrt((double)x)` for an integer, converted back.
    fn sqrt_t(self) -> Self;
    /// `std::isfinite` (integers are finite).
    fn is_finite_t(self) -> bool;
    /// `out << self` with a default `std::ostream`.
    fn cxx_fmt(self) -> String;
}

macro_rules! impl_num_int {
    ($t:ty, $k:ident) => {
        impl Num for $t {
            const KIND: Kind = Kind::$k;
            const LOWEST: Self = <$t>::MIN;
            const MAX: Self = <$t>::MAX;
            #[inline(always)]
            fn to_f64(self) -> f64 {
                self as f64
            }
            #[inline(always)]
            fn to_f32(self) -> f32 {
                self as f32
            }
            #[inline(always)]
            fn to_i128(self) -> i128 {
                self as i128
            }
            #[inline(always)]
            fn from_f64(v: f64) -> Self {
                v as $t
            }
            #[inline(always)]
            fn from_f32(v: f32) -> Self {
                v as $t
            }
            #[inline(always)]
            fn from_i128(v: i128) -> Self {
                v as $t
            }
            #[inline(always)]
            fn neg_fix(self, _original: Self) -> Self {
                self
            }
            fn floor_c(self) -> Self { self }
            fn ceil_c(self) -> Self { self }
            fn round_c(self) -> Self { self }
            fn fabs(self) -> Self { self }
            fn sqrt_t(self) -> Self { (self as f64).sqrt() as $t }
            fn is_finite_t(self) -> bool { true }
            #[inline]
            fn cxx_fmt(self) -> String { self.to_string() }
        }
    };
}
impl_num_int!(i8, I8);
impl_num_int!(i16, I16);
impl_num_int!(i32, I32);
impl_num_int!(i64, I64);
impl_num_int!(u8, U8);
impl_num_int!(u16, U16);
impl_num_int!(u32, U32);
impl_num_int!(u64, U64);

macro_rules! impl_num_float {
    ($t:ty, $k:ident, $i:ty, $lim:expr) => {
        impl Num for $t {
            const KIND: Kind = Kind::$k;
            const LOWEST: Self = <$t>::MIN;
            const MAX: Self = <$t>::MAX;
            #[inline(always)]
            fn to_f64(self) -> f64 {
                self as f64
            }
            #[inline(always)]
            fn to_f32(self) -> f32 {
                self as f32
            }
            #[inline(always)]
            fn to_i128(self) -> i128 {
                self as i128
            }
            #[inline(always)]
            fn from_f64(v: f64) -> Self {
                v as $t
            }
            #[inline(always)]
            fn from_f32(v: f32) -> Self {
                v as $t
            }
            #[inline(always)]
            fn from_i128(v: i128) -> Self {
                v as $t
            }
            // Unary minus of a float flips the sign (0 - x would not).
            #[inline(always)]
            fn neg_fix(self, original: Self) -> Self {
                -original
            }
            #[inline(always)]
            fn floor_c(self) -> Self {
                // Values at least 2^(mantissa bits) are integral, as are
                // infinities; NaN passes through.
                if !(self.abs() < $lim) {
                    return self;
                }
                let t = (self as $i) as $t;
                // floor has the sign of its argument (-0.0 stays -0.0).
                (if t > self { t - 1.0 } else { t }).copysign(self)
            }
            #[inline(always)]
            fn ceil_c(self) -> Self {
                if !(self.abs() < $lim) {
                    return self;
                }
                let t = (self as $i) as $t;
                // ceil of (-1, 0] is -0.0.
                (if t < self { t + 1.0 } else { t }).copysign(self)
            }
            #[inline(always)]
            fn round_c(self) -> Self {
                if !(self.abs() < $lim) {
                    return self;
                }
                let t = (self as $i) as $t;
                // `self - t` is the exact fraction; halves go away from zero.
                (if (self - t).abs() >= 0.5 { t + (1.0 as $t).copysign(self) } else { t })
                    .copysign(self)
            }
            fn fabs(self) -> Self { <$t>::abs(self) }
            fn sqrt_t(self) -> Self { <$t>::sqrt(self) }
            fn is_finite_t(self) -> bool { <$t>::is_finite(self) }
            #[inline]
            fn cxx_fmt(self) -> String { crate::print::g(self) }
        }
    };
}
impl_num_float!(f32, F32, i32, 8388608.0);
impl_num_float!(f64, F64, i64, 4503599627370496.0);

/// `static_cast<T>(u)`.
#[inline(always)]
pub fn conv<U: Num, T: Num>(u: U) -> T {
    match T::KIND {
        Kind::F32 => T::from_f32(u.to_f32()),
        Kind::F64 => T::from_f64(u.to_f64()),
        _ => {
            if U::KIND.is_float() {
                T::from_f64(u.to_f64())
            } else {
                T::from_i128(u.to_i128())
            }
        }
    }
}

/// `static_cast<T>(std::round(u))` (and `ceil`, `floor`): a float is rounded
/// in its own type; an integer goes through `double`.
#[inline(always)]
pub fn round_to<U: Num, T: Num>(u: U) -> T {
    if U::KIND.is_float() { conv(u.round_c()) } else { T::from_f64(u.to_f64()) }
}
#[inline(always)]
pub fn ceil_to<U: Num, T: Num>(u: U) -> T {
    if U::KIND.is_float() { conv(u.ceil_c()) } else { T::from_f64(u.to_f64()) }
}
#[inline(always)]
pub fn floor_to<U: Num, T: Num>(u: U) -> T {
    if U::KIND.is_float() { conv(u.floor_c()) } else { T::from_f64(u.to_f64()) }
}

#[cfg(test)]
mod rounding_tests {
    use super::Num;

    // Not upstream tests: `floor_c`, `ceil_c` and `round_c` replace libm's
    // `floorf`/`ceilf`/`roundf` (and the double ones), so they must agree
    // with them bit for bit on every input class.
    fn edge_f32() -> Vec<f32> {
        let mut v = vec![
            0.0, -0.0, 0.5, -0.5, 0.49999997, -0.49999997, 1.5, -1.5, 2.5, -2.5,
            0.99999994, -0.99999994, 1.0, -1.0, 8388607.5, -8388607.5, 8388608.0,
            -8388608.0, 8388609.0, 16777217.0, f32::MAX, f32::MIN, f32::MIN_POSITIVE,
            -f32::MIN_POSITIVE, 1e-45, -1e-45, f32::INFINITY, f32::NEG_INFINITY,
            2147483520.0, -2147483648.0, 3e9, -3e9, 4194303.5, -4194303.5,
        ];
        let mut s: u64 = 0x9e3779b97f4a7c15;
        // Fewer under Miri, which interprets every operation.
        for _ in 0..if cfg!(miri) { 500 } else { 200_000 } {
            s = s.wrapping_add(0x9e3779b97f4a7c15);
            let mut z = s;
            z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
            z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
            z ^= z >> 31;
            v.push(f32::from_bits(z as u32));
            // Values near integers and halves, where the rounding decides.
            let k = (z >> 32) as i32 % 20000;
            v.push(k as f32 * 0.5 + f32::from_bits(((z >> 8) as u32) & 0x7) * 1e-38);
            v.push(k as f32 * 0.25);
        }
        v
    }

    fn edge_f64() -> Vec<f64> {
        let mut v: Vec<f64> = edge_f32().into_iter().map(|x| x as f64).collect();
        v.extend([
            4503599627370495.5, -4503599627370495.5, 4503599627370496.0, 0.49999999999999994,
            -0.49999999999999994, 9.3e18, -9.3e18, f64::MAX, f64::MIN, 5e-324,
        ]);
        let mut s: u64 = 7;
        for _ in 0..if cfg!(miri) { 500 } else { 200_000 } {
            s = s.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            v.push(f64::from_bits(s));
        }
        v
    }

    fn same32(a: f32, b: f32) -> bool {
        a.to_bits() == b.to_bits() || (a.is_nan() && b.is_nan())
    }
    fn same64(a: f64, b: f64) -> bool {
        a.to_bits() == b.to_bits() || (a.is_nan() && b.is_nan())
    }

    #[test]
    fn f32_rounding_matches_libm() {
        for x in edge_f32() {
            assert!(same32(x.floor_c(), x.floor()), "floor {x:e}: {} vs {}", x.floor_c(), x.floor());
            assert!(same32(x.ceil_c(), x.ceil()), "ceil {x:e}: {} vs {}", x.ceil_c(), x.ceil());
            assert!(same32(x.round_c(), x.round()), "round {x:e}: {} vs {}", x.round_c(), x.round());
        }
    }

    #[test]
    fn f64_rounding_matches_libm() {
        for x in edge_f64() {
            assert!(same64(x.floor_c(), x.floor()), "floor {x:e}");
            assert!(same64(x.ceil_c(), x.ceil()), "ceil {x:e}");
            assert!(same64(x.round_c(), x.round()), "round {x:e}");
        }
    }

    #[test]
    fn integer_rounding_is_identity() {
        assert_eq!(7i64.floor_c(), 7);
        assert_eq!((-7i32).ceil_c(), -7);
        assert_eq!(3u32.round_c(), 3);
    }
}
