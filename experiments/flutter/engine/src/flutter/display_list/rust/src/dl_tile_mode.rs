// Port of flutter/display_list/dl_tile_mode.h

/// How to repeat, fold, or omit colors outside of the typically defined range
/// of the source of the colors (such as the bounds of an image or the defining
/// geometry of a gradient).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[repr(i32)]
pub enum DlTileMode {
    /// Replicate the edge color if the `DlColorSource` draws outside of the
    /// defined bounds.
    Clamp = 0,

    /// Repeat the `DlColorSource`'s defined colors both horizontally and
    /// vertically (or both along and perpendicular to a gradient's geometry).
    Repeat = 1,

    /// Repeat the `DlColorSource`'s colors horizontally and vertically,
    /// alternating mirror images so that adjacent images always seam.
    Mirror = 2,

    /// Only draw within the original domain, return transparent-black everywhere
    /// else.
    Decal = 3,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dl_tile_mode_values() {
        assert_eq!(DlTileMode::Clamp as u8, 0);
        assert_eq!(DlTileMode::Repeat as u8, 1);
        assert_eq!(DlTileMode::Mirror as u8, 2);
        assert_eq!(DlTileMode::Decal as u8, 3);
    }
}
