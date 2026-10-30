// flutter/impeller/geometry/saturated_math.h
//
// Upstream's `saturated::Add`, `Sub`, `AverageScalar` and `Cast` templates,
// chosen by `enable_if` on the argument types, are traits here:
// `SaturatedArith` (signed integers and floats) and `SaturatedCast<To>`.

pub mod saturated {
    use crate::cxx::clamp;
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
                    if self <= <$si>::MIN as $fp {
                        <$si>::MIN
                    } else if self >= <$si>::MAX as $fp {
                        <$si>::MAX
                    } else {
                        // NaN: undefined upstream (static_cast); 0 here.
                        self as $si
                    }
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
