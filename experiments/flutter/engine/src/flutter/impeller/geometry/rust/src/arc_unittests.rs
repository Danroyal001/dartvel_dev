// flutter/impeller/geometry/arc_unittests.cc

#![allow(unused_mut, unused_variables, unused_parens, unused_imports, unused_assignments, unused_braces, clippy::all)]

use crate::prelude::*;
use crate::*;
use crate::arc::Iteration;

// From flutter/impeller/tessellator/tessellator.h, .cc, as test support:
// the Trigs that GetTrigsForDeviceRadius(100) returns, which is all these
// tests use of the tessellator (whose port is its own unit).
// kPrecomputedDivisions[ceil(100)] is 18.
struct Trigs {
  trigs_: Vec<Trig>,
}

impl Trigs {
  fn new(divisions: usize) -> Trigs {
    let mut trigs_ = Vec::with_capacity(divisions + 1);
    let angle_scale: f64 = kPiOver2 as f64 / divisions as f64;
    trigs_.push(Trig::new(1.0, 0.0));
    for i in 1..divisions {
      trigs_.push(Trig::from_radians(Radians::new((i as f64 * angle_scale) as Scalar)));
    }
    trigs_.push(Trig::new(0.0, 1.0));
    Trigs { trigs_ }
  }
  fn size(&self) -> usize {
    self.trigs_.len()
  }
  fn get_steps(&self) -> usize {
    self.trigs_.len() - 1
  }
}

impl std::ops::Index<usize> for Trigs {
  type Output = Trig;
  fn index(&self, index: usize) -> &Trig {
    &self.trigs_[index]
  }
}

/// `Tessellator().GetTrigsForDeviceRadius(100)`.
fn trigs_for_device_radius_100() -> Trigs {
  Trigs::new(18)
}

fn test_arc_iterator(arc_iteration: &Iteration, trigs: &Trigs, start: Degrees, sweep: Degrees, label: &str) {
  expect_point_near!(arc_iteration.start, Matrix::cos_sin(Radians::from(start)));
  expect_point_near!(arc_iteration.end, Matrix::cos_sin(Radians::from(start + sweep)));
  if arc_iteration.quadrant_count == 0 {
    // There is just the begin and end angle and there are no constraints
    // on how far apart they should be, but the end vector should be
    // non-counterclockwise from the start vector.
    expect_ge!(arc_iteration.start.cross(&arc_iteration.end), 0.0f32);
    return;
  }

  let steps = trigs.size() - 1;
  let step_angle: Scalar = kPiOver2 / steps as Scalar;

  // The first and last steps are allowed to be from 0.1 to 1.1 in size
  // as we don't want to iterate an extra step that is less than 0.1 steps
  // from the begin/end angles. We use min/max values that are ever so
  // slightly larger than that to avoid round-off errors.
  let edge_min_cross: Scalar = (step_angle * 0.099).sin();
  let edge_max_cross: Scalar = (step_angle * 1.101).sin();
  let typical_min_cross: Scalar = (step_angle * 0.999).sin();
  let typical_max_cross: Scalar = (step_angle * 1.001).sin();

  let mut cur_vector: Vector2;
  let trace = |cur_vector: &mut Vector2, vector: Vector2, min_cross: Scalar, max_cross: Scalar, label: &str| {
    assert!(cur_vector.cross(&vector) > min_cross, "{label}");
    assert!(cur_vector.cross(&vector) < max_cross, "{label}");
    *cur_vector = vector;
  };

  // The first edge encountered in the loop should be judged by the edge
  // conditions. After that the steps derived from the Trigs should be
  // judged by the typical min/max values.
  let mut min_cross = edge_min_cross;
  let mut max_cross = edge_max_cross;

  cur_vector = arc_iteration.start;
  for i in 0..arc_iteration.quadrant_count {
    let quadrant = &arc_iteration.quadrants[i];
    assert!(quadrant.start_index < quadrant.end_index, "{label}, quadrant: {i}");
    for j in quadrant.start_index..quadrant.end_index {
      trace(&mut cur_vector, trigs[j] * quadrant.axis, min_cross, max_cross, &format!("{label}, quadrant: {i}, step: {j}"));
      // At this point we can guarantee that we've already used the initial
      // min/max values, now replace them with the typical values.
      min_cross = typical_min_cross;
      max_cross = typical_max_cross;
    }
  }

  // The jump to the end angle should be judged by the edge conditions.
  trace(&mut cur_vector, arc_iteration.end, edge_min_cross, edge_max_cross, &format!("{label} step to end"));
}

/// `std::to_string(float)`: "%f".
fn to_string(v: Scalar) -> String {
  crate::print::fixed(v)
}

fn test_full_circle_arc(start: Degrees, sweep: Degrees) {
  let label = format!("{} += {}", to_string(start.degrees), to_string(sweep.degrees));

  let arc = Arc::new(&Rect::make_ltrb(10.0, 10.0, 20.0, 20.0), start, sweep, false);

  let trigs = trigs_for_device_radius_100();
  let steps = trigs.get_steps();
  let arc_iteration = arc.compute_iterations(steps, true);

  expect_eq!(arc_iteration.start, Vector2::new(1.0, 0.0));
  expect_eq!(arc_iteration.quadrant_count, 4usize);
  expect_eq!(arc_iteration.quadrants[0].axis, Vector2::new(1.0, 0.0));
  expect_eq!(arc_iteration.quadrants[0].start_index, 1usize);
  expect_eq!(arc_iteration.quadrants[0].end_index, steps);
  expect_eq!(arc_iteration.quadrants[1].axis, Vector2::new(0.0, 1.0));
  expect_eq!(arc_iteration.quadrants[1].start_index, 0usize);
  expect_eq!(arc_iteration.quadrants[1].end_index, steps);
  expect_eq!(arc_iteration.quadrants[2].axis, Vector2::new(-1.0, 0.0));
  expect_eq!(arc_iteration.quadrants[2].start_index, 0usize);
  expect_eq!(arc_iteration.quadrants[2].end_index, steps);
  expect_eq!(arc_iteration.quadrants[3].axis, Vector2::new(0.0, -1.0));
  expect_eq!(arc_iteration.quadrants[3].start_index, 0usize);
  expect_eq!(arc_iteration.quadrants[3].end_index, steps);
  expect_eq!(arc_iteration.end, Vector2::new(1.0, 0.0));

  // For full circle arcs the original start and sweep are ignored and it
  // returns an iterator that always goes from 0->360.
  test_arc_iterator(&arc_iteration, &trigs, Degrees::new(0.0), Degrees::new(360.0), &format!("Full Circle({label})"));
}

#[test]
fn arc_iterations_full_circle() {
  // Anything with a sweep <=-360 or >=360 is a full circle regardless of
  // starting angle
  for start in (-720..720).step_by(30) {
    for sweep in (360..1080).step_by(45) {
      test_full_circle_arc(Degrees::new(start as f32), Degrees::new(sweep as f32));
      test_full_circle_arc(Degrees::new(start as f32), Degrees::new(-sweep as f32));
    }
  }
}

fn check_one_quadrant(start: Degrees, sweep: Degrees) {
  let mut arc = Arc::new(&Rect::make_ltrb(10.0, 10.0, 20.0, 20.0), start, sweep, false);
  let mut trigs = trigs_for_device_radius_100();
  let mut arc_iteration = arc.compute_iterations(trigs.get_steps(), true);

  expect_point_near!(arc_iteration.start, Matrix::cos_sin(Radians::from(start)));
  expect_eq!(arc_iteration.quadrant_count, 1usize);
  expect_point_near!(arc_iteration.end, Matrix::cos_sin(Radians::from(start + sweep)));

  let label = format!("Quadrant({} += {})", to_string(start.degrees), to_string(sweep.degrees));
  test_arc_iterator(&arc_iteration, &trigs, start, sweep, &format!("{}", label));
}

#[test]
fn arc_iterations_various_start_angles_near_quadrant_axis() {
  let mut trigs = trigs_for_device_radius_100();
  let mut sweep = Degrees::new(45.0);

  for start_i in (-1000..1000).step_by(5) {
    let mut start_degrees = start_i as f32 * 0.01;
    for quadrant in (-360..=360).step_by(90) {
      let mut start = Degrees::new(quadrant as f32 + start_degrees);
      let mut arc = Arc::new(&Rect::make_ltrb(10.0, 10.0, 20.0, 20.0), start, sweep, false);
      let mut arc_iteration = arc.compute_iterations(trigs.get_steps(), true);

      test_arc_iterator(&arc_iteration, &trigs, start, sweep, &format!("Various angles({} += {}", to_string(start.degrees), to_string(sweep.degrees)));
    }
  }
}

#[test]
fn arc_iterations_various_end_angles_near_quadrant_axis() {
  let mut trigs = trigs_for_device_radius_100();

  for sweep_i in (5..20000).step_by(5) {
    let mut sweep = Degrees::new(sweep_i as f32 * 0.01);
    for quadrant in (-360..=360).step_by(90) {
      let mut start = Degrees::new(quadrant as f32 + 80.0);
      let mut arc = Arc::new(&Rect::make_ltrb(10.0, 10.0, 20.0, 20.0), start, sweep, false);
      let mut arc_iteration = arc.compute_iterations(trigs.get_steps(), true);

      test_arc_iterator(&arc_iteration, &trigs, start, sweep, &format!("Various angles({} += {}", to_string(start.degrees), to_string(sweep.degrees)));
    }
  }
}

#[test]
fn arc_iterations_various_tiny_arcs_near_quadrant_axis() {
  let mut trigs = trigs_for_device_radius_100();
  let mut sweep = Degrees::new(0.1f32);

  for start_i in (-1000..1000).step_by(5) {
    let mut start_degrees = start_i as f32 * 0.01;
    for quadrant in (-360..=360).step_by(90) {
      let mut start = Degrees::new(quadrant as f32 + start_degrees);
      let mut arc = Arc::new(&Rect::make_ltrb(10.0, 10.0, 20.0, 20.0), start, sweep, false);
      let mut arc_iteration = arc.compute_iterations(trigs.get_steps(), true);
      expect_eq!(arc_iteration.quadrant_count, 0usize);

      test_arc_iterator(&arc_iteration, &trigs, start, sweep, &format!("Various angles({} += {}", to_string(start.degrees), to_string(sweep.degrees)));
    }
  }
}

#[test]
fn arc_iterations_only_first_quadrant() {
  check_one_quadrant(Degrees::new(90.0 * 0.0 + 30.0), Degrees::new(30.0));
}

#[test]
fn arc_iterations_only_second_quadrant() {
  check_one_quadrant(Degrees::new(90.0 * 1.0 + 30.0), Degrees::new(30.0));
}

#[test]
fn arc_iterations_only_third_quadrant() {
  check_one_quadrant(Degrees::new(90.0 * 2.0 + 30.0), Degrees::new(30.0));
}

#[test]
fn arc_iterations_only_fourth_quadrant() {
  check_one_quadrant(Degrees::new(90.0 * 3.0 + 30.0), Degrees::new(30.0));
}

fn check_five_quadrants(start: Degrees, sweep: Degrees) {
  let label = format!("{} += {}", to_string(start.degrees), to_string(sweep.degrees));
  let mut trigs = trigs_for_device_radius_100();
  let mut arc = Arc::new(&Rect::make_ltrb(10.0, 10.0, 20.0, 20.0), start, sweep, false);
  let mut arc_iteration = arc.compute_iterations(trigs.get_steps(), true);
  let mut steps = trigs.size() - 1;

  expect_point_near!(arc_iteration.start, Matrix::cos_sin(Radians::from(start)));
  expect_eq!(arc_iteration.quadrant_count, 5usize);

  // quadrant 0 start index depends on angle
  expect_eq!(arc_iteration.quadrants[0].end_index, steps);

  expect_eq!(arc_iteration.quadrants[1].start_index, 0usize);
  expect_eq!(arc_iteration.quadrants[1].end_index, steps);

  expect_eq!(arc_iteration.quadrants[2].start_index, 0usize);
  expect_eq!(arc_iteration.quadrants[2].end_index, steps);

  expect_eq!(arc_iteration.quadrants[3].start_index, 0usize);
  expect_eq!(arc_iteration.quadrants[3].end_index, steps);

  expect_eq!(arc_iteration.quadrants[4].start_index, 0usize);
  // quadrant 4 end index depends on angle

  expect_point_near!(arc_iteration.end, Matrix::cos_sin(Radians::from(start + sweep)));

  test_arc_iterator(&arc_iteration, &trigs, start, sweep, &format!("Five quadrants({})", label));
}

#[test]
fn arc_iterations_all_quadrants_from_first() {
  check_five_quadrants(Degrees::new(90.0 * 0.0 + 60.0), Degrees::new(330.0));
}

#[test]
fn arc_iterations_all_quadrants_from_second() {
  check_five_quadrants(Degrees::new(90.0 * 1.0 + 60.0), Degrees::new(330.0));
}

#[test]
fn arc_iterations_all_quadrants_from_third() {
  check_five_quadrants(Degrees::new(90.0 * 2.0 + 60.0), Degrees::new(330.0));
}

#[test]
fn arc_iterations_all_quadrants_from_fourth() {
  check_five_quadrants(Degrees::new(90.0 * 3.0 + 60.0), Degrees::new(330.0));
}

