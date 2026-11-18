// Port of flutter/display_list/dl_sampling_options.h

/// Filter mode for sampling.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[repr(i32)]
pub enum DlFilterMode {
    /// Single sample point (nearest neighbor).
    Nearest = 0,

    /// Interpolate between 2x2 sample points (bilinear interpolation).
    Linear = 1,
}

impl DlFilterMode {
    /// The last filter mode value (equal to Linear).
    #[allow(non_upper_case_globals)]
    pub const kLast: DlFilterMode = DlFilterMode::Linear;
}

/// Image sampling options.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[repr(i32)]
pub enum DlImageSampling {
    /// Nearest neighbor sampling.
    NearestNeighbor = 0,

    /// Linear sampling.
    Linear = 1,

    /// Mipmap linear sampling.
    MipmapLinear = 2,

    /// Cubic sampling.
    Cubic = 3,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dl_filter_mode_values() {
        assert_eq!(DlFilterMode::Nearest as u8, 0);
        assert_eq!(DlFilterMode::Linear as u8, 1);
        assert_eq!(DlFilterMode::kLast as u8, 1);
    }

    #[test]
    fn test_dl_image_sampling_values() {
        assert_eq!(DlImageSampling::NearestNeighbor as u8, 0);
        assert_eq!(DlImageSampling::Linear as u8, 1);
        assert_eq!(DlImageSampling::MipmapLinear as u8, 2);
        assert_eq!(DlImageSampling::Cubic as u8, 3);
    }
}
