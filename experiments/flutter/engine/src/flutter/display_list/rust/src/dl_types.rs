// Port of flutter/display_list/dl_types.h

/// How to combine a new clip with the existing clip.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[repr(i32)]
pub enum DlClipOp {
    /// The new clip is subtracted from the existing clip.
    Difference = 0,
    /// The new clip is intersected with the existing clip.
    Intersect = 1,
}

/// How to interpret a sequence of points when drawing.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[repr(i32)]
pub enum DlPointMode {
    /// Draw each point separately.
    Points = 0,
    /// Draw each separate pair of points as a line segment.
    Lines = 1,
    /// Draw each pair of overlapping points as a line segment.
    Polygon = 2,
}

/// How strictly to constrain the source rectangle when drawing an image.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[repr(i32)]
pub enum DlSrcRectConstraint {
    /// Strictly constrain to the source rectangle.
    Strict = 0,
    /// Fast path: allow sampling outside the source rectangle.
    Fast = 1,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dl_clip_op_values() {
        assert_eq!(DlClipOp::Difference as u8, 0);
        assert_eq!(DlClipOp::Intersect as u8, 1);
    }

    #[test]
    fn test_dl_point_mode_values() {
        assert_eq!(DlPointMode::Points as u8, 0);
        assert_eq!(DlPointMode::Lines as u8, 1);
        assert_eq!(DlPointMode::Polygon as u8, 2);
    }

    #[test]
    fn test_dl_src_rect_constraint_values() {
        assert_eq!(DlSrcRectConstraint::Strict as u8, 0);
        assert_eq!(DlSrcRectConstraint::Fast as u8, 1);
    }
}
