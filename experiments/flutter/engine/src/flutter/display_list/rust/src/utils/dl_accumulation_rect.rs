// Port of flutter/display_list/utils/dl_accumulation_rect.h and .cc.
use impeller_geometry::{point::Point, rect::Rect};

/// Collects bounds and conservatively detects overlap, in insertion order.
///
/// The overlap flag compares each item with the accumulated bounding rectangle,
/// not with the union of the individual shapes. Upper edges are exclusive.
#[derive(Clone, Debug)]
pub struct AccumulationRect {
    min_x: f32,
    min_y: f32,
    max_x: f32,
    max_y: f32,
    overlap_detected: bool,
}

impl Default for AccumulationRect {
    fn default() -> Self {
        Self {
            min_x: f32::INFINITY,
            min_y: f32::INFINITY,
            max_x: f32::NEG_INFINITY,
            max_y: f32::NEG_INFINITY,
            overlap_detected: false,
        }
    }
}

impl AccumulationRect {
    /// Adds a finite point; either non-finite coordinate rejects the point.
    pub fn accumulate(&mut self, x: f32, y: f32) {
        if !x.is_finite() || !y.is_finite() {
            return;
        }
        if x >= self.min_x && x < self.max_x && y >= self.min_y && y < self.max_y {
            self.record_overlapping_bounds();
            return;
        }
        // Keep upstream's strict comparisons: min/max would change signed zero.
        if self.min_x > x {
            self.min_x = x;
        }
        if self.min_y > y {
            self.min_y = y;
        }
        if self.max_x < x {
            self.max_x = x;
        }
        if self.max_y < y {
            self.max_y = y;
        }
    }

    /// Point overload of accumulation.
    #[inline]
    pub fn accumulate_point(&mut self, point: Point) {
        self.accumulate(point.x, point.y);
    }

    /// Adds a nonempty rectangle (including infinite edges, as upstream does).
    pub fn accumulate_rect(&mut self, rect: Rect) {
        if rect.is_empty() {
            return;
        }
        if rect.get_left() < self.max_x
            && rect.get_right() > self.min_x
            && rect.get_top() < self.max_y
            && rect.get_bottom() > self.min_y
        {
            self.record_overlapping_bounds();
        }
        if self.min_x > rect.get_left() {
            self.min_x = rect.get_left();
        }
        if self.min_y > rect.get_top() {
            self.min_y = rect.get_top();
        }
        if self.max_x < rect.get_right() {
            self.max_x = rect.get_right();
        }
        if self.max_y < rect.get_bottom() {
            self.max_y = rect.get_bottom();
        }
    }

    /// Adds another accumulator's nonempty bounds, without inheriting its flag.
    pub fn accumulate_accumulator(&mut self, other: &Self) {
        if other.is_empty() {
            return;
        }
        if other.min_x < self.max_x
            && other.max_x > self.min_x
            && other.min_y < self.max_y
            && other.max_y > self.min_y
        {
            self.record_overlapping_bounds();
        }
        if self.min_x > other.min_x {
            self.min_x = other.min_x;
        }
        if self.min_y > other.min_y {
            self.min_y = other.min_y;
        }
        if self.max_x < other.max_x {
            self.max_x = other.max_x;
        }
        if self.max_y < other.max_y {
            self.max_y = other.max_y;
        }
    }

    /// Whether either dimension has no positive extent.
    #[inline]
    pub fn is_empty(&self) -> bool {
        self.min_x >= self.max_x || self.min_y >= self.max_y
    }
    /// Whether both dimensions have positive extent.
    #[inline]
    pub fn is_not_empty(&self) -> bool {
        self.min_x < self.max_x && self.min_y < self.max_y
    }
    /// Returns the accumulated bounds, preserving degenerate point bounds.
    pub fn get_bounds(&self) -> Rect {
        if self.max_x >= self.min_x && self.max_y >= self.min_y {
            Rect::make_ltrb(self.min_x, self.min_y, self.max_x, self.max_y)
        } else {
            Rect::default()
        }
    }
    /// Restores the initial empty state and clears overlap.
    pub fn reset(&mut self) {
        *self = Self::default();
    }
    /// Whether overlap has been observed or explicitly recorded.
    #[inline]
    pub fn overlap_detected(&self) -> bool {
        self.overlap_detected
    }
    /// Records known overlap.
    #[inline]
    pub fn record_overlapping_bounds(&mut self) {
        self.overlap_detected = true;
    }
}
