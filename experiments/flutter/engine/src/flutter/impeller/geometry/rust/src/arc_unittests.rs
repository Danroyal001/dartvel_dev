// flutter/impeller/geometry/arc_unittests.cc

#![allow(unused_mut, unused_variables, unused_parens, unused_imports, unused_assignments, unused_braces, clippy::all)]

use crate::prelude::*;
use crate::*;

void TestArcIterator(const impeller::Arc::Iteration arc_iteration,
                     const impeller::Tessellator::Trigs& trigs,
                     Degrees start,
                     Degrees sweep,
                     const std::string& label) {
  expect_point_near!(arc_iteration.start, impeller::Matrix::cos_sin(start));
  expect_point_near!(arc_iteration.end, impeller::Matrix::cos_sin(start + sweep));
  if (arc_iteration.quadrant_count == 0u32) {
    // There is just the begin and end angle and there are no constraints
    // on how far apart they should be, but the end vector should be
    // non-counterclockwise from the start vector.
    expect_ge!(arc_iteration.start.cross(arc_iteration.end), 0.0f32);
    return;
  }

  let mut steps = trigs.size() - 1;
  let mut step_angle = kPiOver2 / steps;

  // The first and last steps are allowed to be from 0.1 to 1.1 in size
  // as we don't want to iterate an extra step that is less than 0.1 steps
  // from the begin/end angles. We use min/max values that are ever so
  // slightly larger than that to avoid round-off errors.
  let mut edge_min_cross = f32::sin(step_angle * 0.099f32);
  let mut edge_max_cross = f32::sin(step_angle * 1.101f32);
  let mut typical_min_cross = f32::sin(step_angle * 0.999f32);
  let mut typical_max_cross = f32::sin(step_angle * 1.001f32);

  let mut cur_vector = Vector2::default();
  let mut trace = [&cur_vector](Vector2 vector, Scalar min_cross, Scalar max_cross,
                             const std::string& label) -> void {
    expect_gt!(cur_vector.cross(vector), min_cross);
    expect_lt!(cur_vector.cross(vector), max_cross);
    cur_vector = vector;
  };

  // The first edge encountered in the loop should be judged by the edge
  // conditions. After that the steps derived from the Trigs should be
  // judged by the typical min/max values.
  let mut min_cross = edge_min_cross;
  let mut max_cross = edge_max_cross;

  cur_vector = arc_iteration.start;
  for i in 0..arc_iteration.quadrant_count {
    let mut quadrant = arc_iteration.quadrants[i];
    expect_lt!(quadrant.start_index, quadrant.end_index);
    for j in quadrant.start_index..quadrant.end_index {
      trace(trigs[j] * quadrant.axis, min_cross, max_cross,
            label + ", quadrant: " + std::to_string(i) +
                ", step: " + std::to_string(j));
      // At this point we can guarantee that we've already used the initial
      // min/max values, now replace them with the typical values.
      min_cross = typical_min_cross;
      max_cross = typical_max_cross;
    }
  }

  // The jump to the end angle should be judged by the edge conditions.
  trace(arc_iteration.end, edge_min_cross, edge_max_cross,
        label + " step to end");
}

void TestFullCircleArc(Degrees start, Degrees sweep) {
  let mut label = std::to_string(start.degrees) + " += " + std::to_string(sweep.degrees);

  Arc arc(Rect::make_ltrb(10.0, 10.0, 20.0, 20.0), Degrees::new(start), Degrees::new(sweep),
          false);

  Tessellator tessellator;
  let mut trigs = tessellator.get_trigs_for_device_radius(100);
  let mut steps = trigs.get_steps();
  let mut arc_iteration = arc.compute_iterations(steps);

  expect_eq!(arc_iteration.start, Vector2::new(1.0f32, 0.0f32));
  expect_eq!(arc_iteration.quadrant_count, 4u32);
  expect_eq!(arc_iteration.quadrants[0].axis, Vector2::new(1.0f32, 0.0f32));
  expect_eq!(arc_iteration.quadrants[0].start_index, 1u32);
  expect_eq!(arc_iteration.quadrants[0].end_index, steps);
  expect_eq!(arc_iteration.quadrants[1].axis, Vector2::new(0.0f32, 1.0f32));
  expect_eq!(arc_iteration.quadrants[1].start_index, 0u32);
  expect_eq!(arc_iteration.quadrants[1].end_index, steps);
  expect_eq!(arc_iteration.quadrants[2].axis, Vector2::new(-1.0f32, 0.0f32));
  expect_eq!(arc_iteration.quadrants[2].start_index, 0u32);
  expect_eq!(arc_iteration.quadrants[2].end_index, steps);
  expect_eq!(arc_iteration.quadrants[3].axis, Vector2::new(0.0f32, -1.0f32));
  expect_eq!(arc_iteration.quadrants[3].start_index, 0u32);
  expect_eq!(arc_iteration.quadrants[3].end_index, steps);
  expect_eq!(arc_iteration.end, Vector2::new(1.0f32, 0.0f32));

  // For full circle arcs the original start and sweep are ignored and it
  // returns an iterator that always goes from 0->360.
  TestArcIterator(arc_iteration, trigs, Degrees::new(0.0), Degrees::new(360.0),
                  "Full Circle(" + label + ")");
}

#[test]
fn arc_iterations_full_circle() {
  // Anything with a sweep <=-360 or >=360 is a full circle regardless of
  // starting angle
  for start in (-720..720).step_by(30) {
    for sweep in (360..1080).step_by(45) {
      TestFullCircleArc(Degrees::new(start), Degrees::new(sweep));
      TestFullCircleArc(Degrees::new(start), Degrees::new(-sweep));
    }
  }
}

static void CheckOneQuadrant(Degrees start, Degrees sweep) {
  let mut arc = Arc::new(Rect::make_ltrb(10.0, 10.0, 20.0, 20.0), start, sweep, false);
  Tessellator tessellator;
  let mut trigs = tessellator.get_trigs_for_device_radius(100);
  let mut arc_iteration = arc.compute_iterations(trigs.get_steps());

  expect_point_near!(arc_iteration.start, Matrix::cos_sin(start));
  expect_eq!(arc_iteration.quadrant_count, 1u32);
  expect_point_near!(arc_iteration.end, Matrix::cos_sin(start + sweep));

  std::string label = "Quadrant(" + std::to_string(start.degrees) +
                      " += " + std::to_string(sweep.degrees) + ")";
  TestArcIterator(arc_iteration, trigs, start, sweep, label);
}

#[test]
fn arc_iterations_various_start_angles_near_quadrant_axis() {
  Tessellator tessellator;
  let mut trigs = tessellator.get_trigs_for_device_radius(100);
  let mut sweep = Degrees::new(45.0);

  for start_i in (-1000..1000).step_by(5) {
    let mut start_degrees = start_i * 0.01f32;
    for quadrant in (-360..=360).step_by(90) {
      let mut start = Degrees::new(quadrant + start_degrees);
      let mut arc = Arc::new(Rect::make_ltrb(10.0, 10.0, 20.0, 20.0), start, sweep, false);
      let mut arc_iteration = arc.compute_iterations(trigs.get_steps());

      TestArcIterator(arc_iteration, trigs, start, sweep,
                      "Various angles(" + std::to_string(start.degrees) +
                          " += " + std::to_string(sweep.degrees));
    }
  }
}

#[test]
fn arc_iterations_various_end_angles_near_quadrant_axis() {
  Tessellator tessellator;
  let mut trigs = tessellator.get_trigs_for_device_radius(100);

  for sweep_i in (5..20000).step_by(5) {
    let mut sweep = Degrees::new(sweep_i * 0.01f32);
    for quadrant in (-360..=360).step_by(90) {
      let mut start = Degrees::new(quadrant + 80.0);
      let mut arc = Arc::new(Rect::make_ltrb(10.0, 10.0, 20.0, 20.0), start, sweep, false);
      let mut arc_iteration = arc.compute_iterations(trigs.get_steps());

      TestArcIterator(arc_iteration, trigs, start, sweep,
                      "Various angles(" + std::to_string(start.degrees) +
                          " += " + std::to_string(sweep.degrees));
    }
  }
}

#[test]
fn arc_iterations_various_tiny_arcs_near_quadrant_axis() {
  Tessellator tessellator;
  let mut trigs = tessellator.get_trigs_for_device_radius(100);
  let mut sweep = Degrees::new(0.1f32);

  for start_i in (-1000..1000).step_by(5) {
    let mut start_degrees = start_i * 0.01f32;
    for quadrant in (-360..=360).step_by(90) {
      let mut start = Degrees::new(quadrant + start_degrees);
      let mut arc = Arc::new(Rect::make_ltrb(10.0, 10.0, 20.0, 20.0), start, sweep, false);
      let mut arc_iteration = arc.compute_iterations(trigs.get_steps());
      expect_eq!(arc_iteration.quadrant_count, 0u32);

      TestArcIterator(arc_iteration, trigs, start, sweep,
                      "Various angles(" + std::to_string(start.degrees) +
                          " += " + std::to_string(sweep.degrees));
    }
  }
}

#[test]
fn arc_iterations_only_first_quadrant() {
  CheckOneQuadrant(Degrees::new(90.0 * 0.0 + 30.0), Degrees::new(30.0));
}

#[test]
fn arc_iterations_only_second_quadrant() {
  CheckOneQuadrant(Degrees::new(90.0 * 1.0 + 30.0), Degrees::new(30.0));
}

#[test]
fn arc_iterations_only_third_quadrant() {
  CheckOneQuadrant(Degrees::new(90.0 * 2.0 + 30.0), Degrees::new(30.0));
}

#[test]
fn arc_iterations_only_fourth_quadrant() {
  CheckOneQuadrant(Degrees::new(90.0 * 3.0 + 30.0), Degrees::new(30.0));
}

static void CheckFiveQuadrants(Degrees start, Degrees sweep) {
  std::string label =
      std::to_string(start.degrees) + " += " + std::to_string(sweep.degrees);

  Tessellator tessellator;
  let mut trigs = tessellator.get_trigs_for_device_radius(100);
  let mut arc = Arc::new(Rect::make_ltrb(10.0, 10.0, 20.0, 20.0), start, sweep, false);
  let mut arc_iteration = arc.compute_iterations(trigs.get_steps());
  let mut steps = trigs.size() - 1;

  expect_point_near!(arc_iteration.start, Matrix::cos_sin(start));
  expect_eq!(arc_iteration.quadrant_count, 5u32);

  // quadrant 0 start index depends on angle
  expect_eq!(arc_iteration.quadrants[0].end_index, steps);

  expect_eq!(arc_iteration.quadrants[1].start_index, 0u32);
  expect_eq!(arc_iteration.quadrants[1].end_index, steps);

  expect_eq!(arc_iteration.quadrants[2].start_index, 0u32);
  expect_eq!(arc_iteration.quadrants[2].end_index, steps);

  expect_eq!(arc_iteration.quadrants[3].start_index, 0u32);
  expect_eq!(arc_iteration.quadrants[3].end_index, steps);

  expect_eq!(arc_iteration.quadrants[4].start_index, 0u32);
  // quadrant 4 end index depends on angle

  expect_point_near!(arc_iteration.end, Matrix::cos_sin(start + sweep));

  TestArcIterator(arc_iteration, trigs, start, sweep,
                  "Five quadrants(" + label + ")");
}

#[test]
fn arc_iterations_all_quadrants_from_first() {
  CheckFiveQuadrants(Degrees::new(90.0 * 0.0 + 60.0), Degrees::new(330.0));
}

#[test]
fn arc_iterations_all_quadrants_from_second() {
  CheckFiveQuadrants(Degrees::new(90.0 * 1.0 + 60.0), Degrees::new(330.0));
}

#[test]
fn arc_iterations_all_quadrants_from_third() {
  CheckFiveQuadrants(Degrees::new(90.0 * 2.0 + 60.0), Degrees::new(330.0));
}

#[test]
fn arc_iterations_all_quadrants_from_fourth() {
  CheckFiveQuadrants(Degrees::new(90.0 * 3.0 + 60.0), Degrees::new(330.0));
}

