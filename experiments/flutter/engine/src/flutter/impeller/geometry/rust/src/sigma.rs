// flutter/impeller/geometry/sigma.h, sigma.cc

use crate::scalar::Scalar;

/// For filters that use a Gaussian distribution, this is the `Radius` size
/// to use per `Sigma` (standard deviation).
///
/// This cutoff (sqrt(3)) is taken from Flutter and Skia (where the
/// multiplicative inverse of this constant is used (1 / sqrt(3)):
/// https://api.flutter.dev/flutter/dart-ui/Shadow/convertRadiusToSigma.html
///
/// In practice, this value is somewhat arbitrary, and can be changed to a
/// higher number to integrate more of the Gaussian function and render
/// higher quality blurs (with exponentially diminishing returns for the same
/// sigma input). Making this value any lower results in a noticable loss of
/// quality in the blur.
pub const kKernelRadiusPerSigma: f32 = 1.73205080757;

/// In filters that use Gaussian distributions, "sigma" is a size of one
/// standard deviation in terms of the local space pixel grid of the filter
/// input. In other words, this determines how wide the distribution
/// stretches.
#[derive(Clone, Copy, Debug, Default, PartialEq, PartialOrd)]
pub struct Sigma {
    pub sigma: Scalar,
}

/// For convolution filters, the "radius" is the size of the convolution
/// kernel to use on the local space pixel grid of the filter input.
#[derive(Clone, Copy, Debug, Default, PartialEq, PartialOrd)]
pub struct Radius {
    pub radius: Scalar,
}

impl Sigma {
    #[inline]
    pub const fn new(p_sigma: Scalar) -> Sigma {
        Sigma { sigma: p_sigma }
    }
}

impl Radius {
    #[inline]
    pub const fn new(p_radius: Scalar) -> Radius {
        Radius { radius: p_radius }
    }
}

/// `Sigma::operator Radius()`.
impl From<Sigma> for Radius {
    #[inline]
    fn from(s: Sigma) -> Radius {
        Radius { radius: if s.sigma > 0.5 { (s.sigma - 0.5) * kKernelRadiusPerSigma } else { 0.0 } }
    }
}

/// `Radius::operator Sigma()`.
impl From<Radius> for Sigma {
    #[inline]
    fn from(r: Radius) -> Sigma {
        Sigma { sigma: if r.radius > 0.0 { r.radius / kKernelRadiusPerSigma + 0.5 } else { 0.0 } }
    }
}
