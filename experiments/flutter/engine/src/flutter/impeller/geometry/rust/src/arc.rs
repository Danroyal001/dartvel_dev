// flutter/impeller/geometry/arc.h, arc.cc

use std::fmt;

use crate::matrix::Matrix;
use crate::point::{Point, Vector2, kQuadrantAxes};
use crate::rect::Rect;
use crate::scalar::{Degrees, Radians, Scalar};
use crate::size::Size;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Arc {
    bounds_: Rect,
    start_: Degrees,
    sweep_: Degrees,
    include_center_: bool,
}

/// A structure to describe the iteration through a set of angle vectors in
/// a |Trig| object to render the points along an arc.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Iteration {
    /// The start direction of the arc, as a unit vector.
    pub start: Vector2,
    /// The end direction of the arc, as a unit vector.
    pub end: Vector2,
    /// The number of quadrants to iterate.
    pub quadrant_count: usize,
    /// The quadrants (at most 9, for a 720 degree arc that starts and ends
    /// in the middle of a quadrant).
    pub quadrants: [Quadrant; 9],
}

/// The rendering of a quadrant: axis, then the indices of the |Trig|
/// vectors to use.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Quadrant {
    pub axis: Vector2,
    pub start_index: usize,
    pub end_index: usize,
}

impl Quadrant {
    pub fn get_point_count(&self) -> usize {
        fml::fml_dcheck_at!(
            "flutter/impeller/geometry/arc.h",
            51,
            "start_index < end_index",
            self.start_index < self.end_index
        );
        self.end_index.wrapping_sub(self.start_index)
    }
}

impl Iteration {
    pub fn get_point_count(&self) -> usize {
        let mut count: usize = 2;
        for i in 0..self.quadrant_count {
            count = count.wrapping_add(self.quadrants[i].get_point_count());
        }
        count
    }
}

impl Arc {
    pub fn new(bounds: &Rect, mut start: Degrees, mut sweep: Degrees, include_center: bool) -> Arc {
        if bounds.is_finite() && start.is_finite() && sweep.is_finite() {
            if sweep.degrees < 0.0 {
                start = start + sweep;
                sweep = -sweep;
            }
            if sweep.degrees > 360.0 {
                // Remove extra full sweeps but leave it more than 360
                sweep.degrees = 360.0 + sweep.degrees % 360.0;
            }
        } else {
            // Don't bother sweeping any distance if anything is non-finite.
            sweep = Degrees::new(0.0);
            if !start.is_finite() || !bounds.is_finite() {
                // We can maintain start if both it and bounds are finite.
                start = Degrees::new(0.0);
            }
        }
        Arc { bounds_: *bounds, start_: start, sweep_: sweep, include_center_: include_center }
    }

    /// Return the bounds of the oval in which this arc is inscribed.
    pub fn get_oval_bounds(&self) -> &Rect {
        &self.bounds_
    }

    /// Returns the center of the oval bounds.
    pub fn get_oval_center(&self) -> Point {
        self.bounds_.get_center()
    }

    /// Returns the size of the oval bounds.
    pub fn get_oval_size(&self) -> Size {
        self.bounds_.get_size()
    }

    /// Return the tight bounds of the arc taking into account its specific
    /// start and sweep angles and the center if included.
    pub fn get_tight_arc_bounds(&self) -> Rect {
        if self.is_full_circle() {
            return self.bounds_;
        }

        let start_angle = self.start_.get_positive();
        let end_angle = start_angle + self.sweep_;
        fml::fml_dcheck_at!(
            "flutter/impeller/geometry/arc.cc",
            66,
            "start_angle.degrees >= 0 && start_angle.degrees < 360",
            start_angle.degrees >= 0.0 && start_angle.degrees < 360.0
        );
        fml::fml_dcheck_at!(
            "flutter/impeller/geometry/arc.cc",
            67,
            "end_angle > start_angle && end_angle.degrees < 720",
            end_angle > start_angle && end_angle.degrees < 720.0
        );

        // 1. start vector
        // 2. end vector
        // 3. optional center
        // 4-7. optional quadrant extrema
        let mut extrema = [Point::default(); 7];
        let mut count: usize = 0;

        extrema[count] = Matrix::cos_sin(Radians::from(start_angle));
        count += 1;
        extrema[count] = Matrix::cos_sin(Radians::from(end_angle));
        count += 1;

        if self.include_center_ {
            extrema[count] = Point::new(0.0, 0.0);
            count += 1;
        }

        // cur_axis will be pre-incremented before recording the following
        // axis, it will initially be the axis at or before the start of the
        // arc.
        let mut cur_axis: i32 = (start_angle.degrees / 90.0).floor() as i32;
        // end_axis is a vector at or after the end of the arc.
        let end_axis: i32 = (end_angle.degrees / 90.0).ceil() as i32;
        loop {
            cur_axis = cur_axis.wrapping_add(1);
            if cur_axis >= end_axis {
                break;
            }
            extrema[count] = kQuadrantAxes[(cur_axis & 3) as usize];
            count += 1;
        }

        fml::fml_dcheck_at!("flutter/impeller/geometry/arc.cc", 91, "count <= 7", count <= 7);

        let center = self.bounds_.get_center();
        let radii: Size = self.bounds_.get_size() * 0.5;

        for e in extrema.iter_mut().take(count) {
            *e = center + *e * radii;
        }
        Rect::make_point_bounds(&extrema[..count]).unwrap_or_default()
    }

    /// Return the start angle of the arc.
    pub fn get_start(&self) -> Degrees {
        self.start_
    }

    /// Return the sweep angle of the arc.
    pub fn get_sweep(&self) -> Degrees {
        self.sweep_
    }

    /// Return true if the arc includes the center of its oval.
    pub fn include_center(&self) -> bool {
        self.include_center_
    }

    pub fn is_perfect_circle(&self) -> bool {
        self.bounds_.is_square()
    }

    pub fn is_full_circle(&self) -> bool {
        self.sweep_.degrees >= 360.0
    }

    /// Return a |Iteration| structure to describe the iteration through a
    /// set of Trig vectors to render the points along this arc.
    pub fn compute_iterations(&self, step_count: usize, simplify_360: bool) -> Iteration {
        if self.sweep_.degrees == 0.0 {
            return Iteration::default();
        }

        fml::fml_dcheck_at!("flutter/impeller/geometry/arc.cc", 108, "sweep_.degrees >= 0", self.sweep_.degrees >= 0.0);

        if simplify_360 && self.sweep_.degrees >= 360.0 {
            return compute_circle_arc_iterations(step_count);
        }
        fml::fml_dcheck_at!("flutter/impeller/geometry/arc.cc", 113, "sweep_.degrees < 720", self.sweep_.degrees < 720.0);

        let start = self.start_.get_positive();
        let end = start + self.sweep_;
        fml::fml_dcheck_at!(
            "flutter/impeller/geometry/arc.cc",
            117,
            "start.degrees >= 0.0f && start.degrees < 360.0f",
            start.degrees >= 0.0 && start.degrees < 360.0
        );
        fml::fml_dcheck_at!("flutter/impeller/geometry/arc.cc", 118, "end >= start", end >= start);
        fml::fml_dcheck_at!(
            "flutter/impeller/geometry/arc.cc",
            119,
            "end.degrees < start.degrees + (simplify_360 ? 360.0f : 720.0f)",
            end.degrees < start.degrees + if simplify_360 { 360.0 } else { 720.0 }
        );

        let mut iterations = Iteration::default();
        iterations.start = Matrix::cos_sin(Radians::from(start));
        iterations.end = Matrix::cos_sin(Radians::from(end));

        // We nudge the start and stop by 1/10th of a step so we don't end
        // up with degenerately small steps at the start and end of the arc.
        let nudge = Degrees::new((90.0 / step_count as Scalar) * 0.1);

        if (start + nudge) >= (end - nudge) {
            iterations.quadrant_count = 0;
            return iterations;
        }

        let mut cur_quadrant: i32 = ((start + nudge).degrees / 90.0).floor() as i32;
        let end_quadrant: i32 = ((end - nudge).degrees / 90.0).floor() as i32;
        fml::fml_dcheck_at!(
            "flutter/impeller/geometry/arc.cc",
            139,
            "cur_quadrant >= 0 && cur_quadrant <= 4",
            (0..=4).contains(&cur_quadrant)
        );
        fml::fml_dcheck_at!(
            "flutter/impeller/geometry/arc.cc",
            141,
            "end_quadrant >= cur_quadrant && end_quadrant <= cur_quadrant + 8",
            end_quadrant >= cur_quadrant && end_quadrant <= cur_quadrant + 8
        );
        fml::fml_dcheck_at!(
            "flutter/impeller/geometry/arc.cc",
            143,
            "cur_quadrant * 90 <= (start + nudge).degrees",
            (cur_quadrant * 90) as Scalar <= (start + nudge).degrees
        );
        fml::fml_dcheck_at!(
            "flutter/impeller/geometry/arc.cc",
            144,
            "end_quadrant * 90 + 90 >= (end - nudge).degrees",
            (end_quadrant * 90 + 90) as Scalar >= (end - nudge).degrees
        );

        let next_step = |angle: Degrees, quadrant: i32| -> usize {
            let quadrant_fract: Scalar = angle.degrees / 90.0 - quadrant as Scalar;
            (quadrant_fract * step_count as Scalar).ceil() as usize
        };

        let mut i: usize = 0;
        iterations.quadrants[i] = Quadrant {
            axis: kQuadrantAxes[(cur_quadrant & 3) as usize],
            start_index: next_step(start + nudge, cur_quadrant),
            end_index: step_count,
        };
        if iterations.quadrants[0].end_index > iterations.quadrants[0].start_index {
            i += 1;
        }
        while cur_quadrant < end_quadrant {
            cur_quadrant += 1;
            iterations.quadrants[i] =
                Quadrant { axis: kQuadrantAxes[(cur_quadrant % 4) as usize], start_index: 0, end_index: step_count };
            i += 1;
        }
        fml::fml_dcheck_at!("flutter/impeller/geometry/arc.cc", 167, "i <= 9", i <= 9);
        if i > 0 {
            iterations.quadrants[i - 1].end_index = next_step(end - nudge, cur_quadrant);
            if iterations.quadrants[i - 1].end_index <= iterations.quadrants[i - 1].start_index {
                i -= 1;
            }
        }
        iterations.quadrant_count = i;
        iterations
    }
}

fn compute_circle_arc_iterations(step_count: usize) -> Iteration {
    Iteration {
        start: Vector2::new(1.0, 0.0),
        end: Vector2::new(1.0, 0.0),
        quadrant_count: 4,
        quadrants: [
            Quadrant { axis: kQuadrantAxes[0], start_index: 1, end_index: step_count },
            Quadrant { axis: kQuadrantAxes[1], start_index: 0, end_index: step_count },
            Quadrant { axis: kQuadrantAxes[2], start_index: 0, end_index: step_count },
            Quadrant { axis: kQuadrantAxes[3], start_index: 0, end_index: step_count },
            Quadrant { axis: Vector2::default(), start_index: 0, end_index: 0 },
            Quadrant::default(),
            Quadrant::default(),
            Quadrant::default(),
            Quadrant::default(),
        ],
    }
}

impl fmt::Display for Arc {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "Arc({}, {} + {}{}",
            self.get_oval_bounds(),
            self.get_start(),
            self.get_sweep(),
            if self.include_center() { ", with center)" } else { ", without center)" }
        )
    }
}
