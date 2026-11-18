// flutter/impeller/geometry/saturated_math.h
//
// Upstream's `saturated::Add`, `Sub`, `AverageScalar` and `Cast` templates,
// chosen by `enable_if` on the argument types, are traits here:
// `SaturatedArith` (signed integers and floats) and `SaturatedCast<To>`.

pub mod saturated {
    use crate::cxx::{Num, clamp};
    use crate::scalar::Scalar;

    pub trait SaturatedArith: Copy {
        fn saturated_add(self, distance: Self) -> Self;
        fn saturated_sub(self, lower: Self) -> Self;
        fn average_scalar(self, b: Self) -> Scalar;
    }

    macro_rules! signed_int {
        ($($t:ty),*) => {$(
            impl SaturatedArith for $t {
                #[inline(always)]
                fn saturated_add(self, distance: $t) -> $t {
                    let location = self;
                    if location >= 0 {
                        if distance > <$t>::MAX - location {
                            return <$t>::MAX;
                        }
                    } else if distance < <$t>::MIN - location {
                        return <$t>::MIN;
                    }
                    location + distance
                }
                #[inline(always)]
                fn saturated_sub(self, lower: $t) -> $t {
                    let upper = self;
                    if upper >= 0 {
                        if lower < 0 && upper > <$t>::MAX + lower {
                            return <$t>::MAX;
                        }
                    } else if lower > 0 && upper < <$t>::MIN + lower {
                        return <$t>::MIN;
                    }
                    upper - lower
                }
                // scalbn has an implementation for ints that converts to
                // double while adjusting the exponent.
                #[inline(always)]
                fn average_scalar(self, b: $t) -> Scalar {
                    (self as f64 * 0.5 + b as f64 * 0.5) as Scalar
                }
            }
        )*};
    }
    signed_int!(i8, i16, i32, i64);

    // scalbn(x, -1) is x * 0.5 exactly (both round a denormal result to
    // nearest even).
    impl SaturatedArith for f32 {
        #[inline(always)]
        fn saturated_add(self, distance: f32) -> f32 {
            self + distance
        }
        #[inline(always)]
        fn saturated_sub(self, lower: f32) -> f32 {
            self - lower
        }
        #[inline(always)]
        fn average_scalar(self, b: f32) -> Scalar {
            self * 0.5 + b * 0.5
        }
    }

    impl SaturatedArith for f64 {
        #[inline(always)]
        fn saturated_add(self, distance: f64) -> f64 {
            self + distance
        }
        #[inline(always)]
        fn saturated_sub(self, lower: f64) -> f64 {
            self - lower
        }
        #[inline(always)]
        fn average_scalar(self, b: f64) -> Scalar {
            (self * 0.5 + b * 0.5) as Scalar
        }
    }

    #[inline(always)]
    pub fn add<T: SaturatedArith>(location: T, distance: T) -> T {
        location.saturated_add(distance)
    }

    #[inline(always)]
    pub fn sub<T: SaturatedArith>(upper: T, lower: T) -> T {
        upper.saturated_sub(lower)
    }

    #[inline(always)]
    pub fn average_scalar<T: SaturatedArith>(a: T, b: T) -> Scalar {
        a.average_scalar(b)
    }

    /// `saturated::Cast<From, To>`.
    pub trait SaturatedCast<To>: Copy {
        fn saturated_cast(self) -> To;

        /// `saturated::Cast<From, To>(floor(v))`, as RoundOut and RoundIn
        /// write it.
        #[inline(always)]
        fn saturated_cast_floor(self) -> To
        where
            Self: Num,
        {
            self.floor_c().saturated_cast()
        }

        /// `saturated::Cast<From, To>(ceil(v))`.
        #[inline(always)]
        fn saturated_cast_ceil(self) -> To
        where
            Self: Num,
        {
            self.ceil_c().saturated_cast()
        }
    }

    macro_rules! same {
        ($($t:ty),*) => {$(
            impl SaturatedCast<$t> for $t {
                #[inline(always)]
                fn saturated_cast(self) -> $t { self }
            }
        )*};
    }
    same!(i8, i16, i32, i64, f32, f64);

    macro_rules! float_to_int {
        ($fp:ty => $($si:ty),*) => {$(
            impl SaturatedCast<$si> for $fp {
                #[inline(always)]
                fn saturated_cast(self) -> $si {
                    // Upstream: `v <= (FP)MIN` gives MIN, `v >= (FP)MAX` gives
                    // MAX, anything else `static_cast`s (undefined for NaN).
                    // Rust's `as` truncates and saturates to those same
                    // values at both ends, and gives 0 for NaN, as upstream's
                    // CastingNaNScalarToSignedIntProducesZero expects.
                    self as $si
                }

                // The same integer, computed in the integer domain: truncate
                // (saturating, NaN to 0), then step down where that rounded
                // up. Below 2^p the truncation is exact to compare; above it
                // the value is integral, so it compares equal; past the
                // integer range the step saturates, as floor then Cast does.
                #[inline(always)]
                fn saturated_cast_floor(self) -> $si {
                    let i = self as $si;
                    if (i as $fp) > self { i.saturating_sub(1) } else { i }
                }

                #[inline(always)]
                fn saturated_cast_ceil(self) -> $si {
                    let i = self as $si;
                    if (i as $fp) < self { i.saturating_add(1) } else { i }
                }
            }
        )*};
    }
    float_to_int!(f32 => i8, i16, i32, i64);
    float_to_int!(f64 => i8, i16, i32, i64);

    impl SaturatedCast<f32> for f64 {
        #[inline(always)]
        fn saturated_cast(self) -> f32 {
            if self.is_finite() {
                // Avoid truncation to inf/-inf.
                clamp(self as f32, f32::MIN, f32::MAX)
            } else {
                self as f32
            }
        }
    }

    impl SaturatedCast<f64> for f32 {
        #[inline(always)]
        fn saturated_cast(self) -> f64 {
            if self.is_finite() { clamp(self as f64, f64::MIN, f64::MAX) } else { self as f64 }
        }
    }

    #[inline(always)]
    pub fn cast<F: SaturatedCast<T>, T>(v: F) -> T {
        v.saturated_cast()
    }
}

#[cfg(test)]
mod fused_rounding_tests {
    // Not upstream tests: `saturated_cast_floor`/`_ceil` fuse RoundOut's and
    // RoundIn's `saturated::Cast(floor(v))` and `Cast(ceil(v))`, so they must
    // give the same integer for every float.
    use super::saturated::SaturatedCast;
    use crate::cxx::Num;

    fn values() -> Vec<f64> {
        let mut v = vec![
            0.0, -0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 0.99999994, -0.99999994, 8388607.5,
            -8388607.5, 8388608.0, -8388608.0, 127.0, 127.5, 128.0, -128.0, -128.5, -129.0,
            32767.5, -32768.5, 2147483520.0, 2147483647.0, 2147483648.0, -2147483648.0,
            -2147483649.0, 9.2233715e18, 9.223372e18, -9.223372e18, -9.3e18, 1e30, -1e30,
            f64::INFINITY, f64::NEG_INFINITY, f64::NAN, 4503599627370495.5, -4503599627370495.5,
        ];
        let mut s: u64 = 99;
        for _ in 0..if cfg!(miri) { 300 } else { 100_000 } {
            s = s.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            v.push(f32::from_bits((s >> 32) as u32) as f64);
            v.push(f64::from_bits(s));
            v.push(((s >> 40) as i32 as f64) * 0.25);
        }
        v
    }

    macro_rules! check {
        ($fp:ty => $($si:ty),*) => {$(
            for x in values() {
                let x = x as $fp;
                let floor: $si = x.floor_c().saturated_cast();
                let ceil: $si = x.ceil_c().saturated_cast();
                assert_eq!(<$fp as SaturatedCast<$si>>::saturated_cast_floor(x), floor, "floor {x:e}");
                assert_eq!(<$fp as SaturatedCast<$si>>::saturated_cast_ceil(x), ceil, "ceil {x:e}");
            }
        )*};
    }

    #[test]
    fn fused_floor_and_ceil_casts_match_floor_then_cast() {
        check!(f32 => i8, i16, i32, i64);
        check!(f64 => i8, i16, i32, i64);
    }
}
