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
    let r = x.round();
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
    /// `std::floor`, `std::ceil`, `std::round`, `std::fabs` of the value as
    /// the type's own overload computes it (integers go through double).
    fn floor_t(self) -> f64;
    fn ceil_t(self) -> f64;
    fn round_t(self) -> f64;
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
            fn floor_t(self) -> f64 {
                self as f64
            }
            fn ceil_t(self) -> f64 {
                self as f64
            }
            fn round_t(self) -> f64 {
                self as f64
            }
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
            // Unary minus of a float flips the sign (0 - x would not).
            #[inline(always)]
            fn neg_fix(self, original: Self) -> Self {
                -original
            }
            fn floor_t(self) -> f64 {
                self.floor() as f64
            }
            fn ceil_t(self) -> f64 {
                self.ceil() as f64
            }
            fn round_t(self) -> f64 {
                self.round() as f64
            }
        }
    };
}
impl_num_float!(f32, F32);
impl_num_float!(f64, F64);
