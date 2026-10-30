// Port of `Variance` in _fe_analyzer_shared's lib/src/types/shared_type.dart.
//
// It lives in this crate because the `_fe_analyzer_shared` crate was being
// changed by another port while this one was written; it belongs there.

/// The variance of a type parameter `X` in a type `T`.
#[allow(non_camel_case_types)]
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
#[repr(u8)]
pub enum Variance {
    /// Used when `X` does not occur free in `T`.
    unrelated = 0,
    /// Used when `X` occurs free in `T`, and `U <: V` implies `[U/X]T <: [V/X]T`.
    covariant = 1,
    /// Used when `X` occurs free in `T`, and `U <: V` implies `[V/X]T <: [U/X]T`.
    contravariant = 2,
    /// Used when there exists a pair `U` and `V` such that `U <: V`, but
    /// `[U/X]T` and `[V/X]T` are incomparable.
    invariant = 3,
}

impl Variance {
    pub fn keyword(self) -> &'static str {
        match self {
            Variance::unrelated => "",
            Variance::covariant => "out",
            Variance::contravariant => "in",
            Variance::invariant => "inout",
        }
    }

    /// `Variance.fromEncoding`.
    pub fn from_encoding(encoding: u8) -> Variance {
        match encoding {
            0 => Variance::unrelated,
            1 => Variance::covariant,
            2 => Variance::contravariant,
            3 => Variance::invariant,
            _ => panic!("RangeError: {encoding}"),
        }
    }

    /// `Variance.fromKeywordString`.
    pub fn from_keyword_string(keyword_string: &str) -> Variance {
        match keyword_string {
            "in" => Variance::contravariant,
            "inout" => Variance::invariant,
            "out" => Variance::covariant,
            "unrelated" => Variance::unrelated,
            _ => panic!("ArgumentError: Invalid keyword string for variance: {keyword_string}"),
        }
    }

    pub fn is_contravariant(self) -> bool {
        self == Variance::contravariant
    }

    pub fn is_covariant(self) -> bool {
        self == Variance::covariant
    }

    pub fn is_invariant(self) -> bool {
        self == Variance::invariant
    }

    pub fn is_unrelated(self) -> bool {
        self == Variance::unrelated
    }

    /// Combines variances of `X` in `T` and `Y` in `S` into variance of `X`
    /// in `[Y/T]S`.
    pub fn combine(self, other: Variance) -> Variance {
        if self.is_unrelated() || other.is_unrelated() {
            return Variance::unrelated;
        }
        if self.is_invariant() || other.is_invariant() {
            return Variance::invariant;
        }
        if self == other { Variance::covariant } else { Variance::contravariant }
    }

    /// The meet of two elements of the variance lattice, where unrelated is
    /// the top and invariant the bottom.
    pub fn meet(self, other: Variance) -> Variance {
        Variance::from_encoding(self as u8 | other as u8)
    }
}
