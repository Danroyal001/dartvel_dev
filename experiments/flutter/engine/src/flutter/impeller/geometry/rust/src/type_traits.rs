// flutter/impeller/geometry/type_traits.h (type_traits.cc is empty)
//
// Upstream's `MixedOp<F, I>` enables the operators that combine a floating
// point TPoint with an integral one. The port expresses the same constraint
// with the `Num` kinds in `crate::cxx`: the mixed operators are implemented
// for the instantiations upstream has (`Point` with `IPoint`/`IPoint32`).

use crate::cxx::Num;

#[inline]
/// True when `F` is floating point and `I` integral, as `MixedOp_` requires.
pub const fn mixed_op<F: Num, I: Num>() -> bool {
    F::KIND.is_float() && !I::KIND.is_float()
}
