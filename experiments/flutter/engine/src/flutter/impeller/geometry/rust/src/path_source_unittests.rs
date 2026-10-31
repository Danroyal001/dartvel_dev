// flutter/impeller/geometry/path_source_unittests.cc

#![allow(unused_mut, unused_variables, unused_parens, unused_imports, unused_assignments, unused_braces, clippy::all)]

use crate::prelude::*;
use crate::*;

#[test]
fn rect_source_test() {
  let mut rect = Rect::make_ltrb(10.0, 15.0, 20.0, 30.0);
  let source = RectPathSource::new(&rect);

  expect_true!(source.is_convex());
  expect_eq!(source.get_fill_type(), FillType::kNonZero);
  expect_eq!(source.get_bounds(), Rect::make_ltrb(10.0, 15.0, 20.0, 30.0));

  let mut receiver = DlPathReceiverMock::default();

  {

    receiver.expect(Call::MoveTo(Point::new(10.0, 15.0), true), false);
    receiver.expect(Call::LineTo(Point::new(20.0, 15.0)), false);
    receiver.expect(Call::LineTo(Point::new(20.0, 30.0)), false);
    receiver.expect(Call::LineTo(Point::new(10.0, 30.0)), false);
    receiver.expect(Call::LineTo(Point::new(10.0, 15.0)), false);
    receiver.expect(Call::Close, false);
  }

  source.dispatch(&mut receiver);
  receiver.verify();
}

#[test]
fn ellipse_source_test() {
  let mut rect = Rect::make_ltrb(10.0, 15.0, 20.0, 30.0);
  let source = EllipsePathSource::new(&rect);

  expect_true!(source.is_convex());
  expect_eq!(source.get_fill_type(), FillType::kNonZero);
  expect_eq!(source.get_bounds(), Rect::make_ltrb(10.0, 15.0, 20.0, 30.0));

  let mut receiver = DlPathReceiverMock::default();

  {

    receiver.expect(Call::MoveTo(Point::new(10.0, 22.5), true), false);
    receiver.expect(Call::ConicTo(Point::new(10.0, 15.0), Point::new(15.0, 15.0), kSqrt2Over2), false);
    receiver.expect(Call::ConicTo(Point::new(20.0, 15.0), Point::new(20.0, 22.5), kSqrt2Over2), false);
    receiver.expect(Call::ConicTo(Point::new(20.0, 30.0), Point::new(15.0, 30.0), kSqrt2Over2), false);
    receiver.expect(Call::ConicTo(Point::new(10.0, 30.0), Point::new(10.0, 22.5), kSqrt2Over2), false);
    receiver.expect(Call::Close, false);
  }

  source.dispatch(&mut receiver);
  receiver.verify();
}

#[test]
fn round_rect_source_test() {
  let mut rect = Rect::make_ltrb(10.0, 15.0, 40.0, 60.0);
  let mut radii = RoundingRadii {
      top_left: Size::new(1.0, 11.0),
      top_right: Size::new(2.0, 12.0),
      bottom_left: Size::new(4.0, 14.0),
      bottom_right: Size::new(3.0, 13.0),
    ..Default::default()
  };
  let mut round_rect = RoundRect::make_rect_radii(&rect, &radii);
  let source = RoundRectPathSource::new(&round_rect);

  expect_true!(source.is_convex());
  expect_eq!(source.get_fill_type(), FillType::kNonZero);
  expect_eq!(source.get_bounds(), Rect::make_ltrb(10.0, 15.0, 40.0, 60.0));

  let mut receiver = DlPathReceiverMock::default();

  {

    receiver.expect(Call::MoveTo(Point::new(11.0, 15.0), true), false);
    receiver.expect(Call::LineTo(Point::new(38.0, 15.0)), false);
    receiver.expect(Call::ConicTo(Point::new(40.0, 15.0), Point::new(40.0, 27.0), kSqrt2Over2), false);
    receiver.expect(Call::LineTo(Point::new(40.0, 47.0)), false);
    receiver.expect(Call::ConicTo(Point::new(40.0, 60.0), Point::new(37.0, 60.0), kSqrt2Over2), false);
    receiver.expect(Call::LineTo(Point::new(14.0, 60.0)), false);
    receiver.expect(Call::ConicTo(Point::new(10.0, 60.0), Point::new(10.0, 46.0), kSqrt2Over2), false);
    receiver.expect(Call::LineTo(Point::new(10.0, 26.0)), false);
    receiver.expect(Call::ConicTo(Point::new(10.0, 15.0), Point::new(11.0, 15.0), kSqrt2Over2), false);
    receiver.expect(Call::Close, false);
  }

  source.dispatch(&mut receiver);
  receiver.verify();
}

#[test]
fn diff_round_rect_source_test() {
  let mut outer_rect = Rect::make_ltrb(10.0, 15.0, 200.0, 300.0);
  let mut inner_rect = Rect::make_ltrb(50.0, 60.0, 100.0, 200.0);
  expect_true!(outer_rect.contains_rect(&inner_rect));
  let mut radii = RoundingRadii {
      top_left: Size::new(1.0, 11.0),
      top_right: Size::new(2.0, 12.0),
      bottom_left: Size::new(4.0, 14.0),
      bottom_right: Size::new(3.0, 13.0),
    ..Default::default()
  };
  let mut outer_rrect = RoundRect::make_rect_radii(&outer_rect, &radii);
  let mut inner_rrect = RoundRect::make_rect_radii(&inner_rect, &radii);
  let source = DiffRoundRectPathSource::new(&outer_rrect, &inner_rrect);

  expect_false!(source.is_convex());
  expect_eq!(source.get_fill_type(), FillType::kOdd);
  expect_eq!(source.get_bounds(), Rect::make_ltrb(10.0, 15.0, 200.0, 300.0));

  let mut receiver = DlPathReceiverMock::default();

  {

    receiver.expect(Call::MoveTo(Point::new(11.0, 15.0), true), false);
    receiver.expect(Call::LineTo(Point::new(198.0, 15.0)), false);
    receiver.expect(Call::ConicTo(Point::new(200.0, 15.0), Point::new(200.0, 27.0), kSqrt2Over2), false);
    receiver.expect(Call::LineTo(Point::new(200.0, 287.0)), false);
    receiver.expect(Call::ConicTo(Point::new(200.0, 300.0), Point::new(197.0, 300.0), kSqrt2Over2), false);
    receiver.expect(Call::LineTo(Point::new(14.0, 300.0)), false);
    receiver.expect(Call::ConicTo(Point::new(10.0, 300.0), Point::new(10.0, 286.0), kSqrt2Over2), false);
    receiver.expect(Call::LineTo(Point::new(10.0, 26.0)), false);
    receiver.expect(Call::ConicTo(Point::new(10.0, 15.0), Point::new(11.0, 15.0), kSqrt2Over2), false);
    // RetiresOnSaturation keeps identical calls from matching each other
    receiver.expect(Call::Close, false);

    receiver.expect(Call::MoveTo(Point::new(51.0, 60.0), true), false);
    receiver.expect(Call::LineTo(Point::new(98.0, 60.0)), false);
    receiver.expect(Call::ConicTo(Point::new(100.0, 60.0), Point::new(100.0, 72.0), kSqrt2Over2), false);
    receiver.expect(Call::LineTo(Point::new(100.0, 187.0)), false);
    receiver.expect(Call::ConicTo(Point::new(100.0, 200.0), Point::new(97.0, 200.0), kSqrt2Over2), false);
    receiver.expect(Call::LineTo(Point::new(54.0, 200.0)), false);
    receiver.expect(Call::ConicTo(Point::new(50.0, 200.0), Point::new(50.0, 186.0), kSqrt2Over2), false);
    receiver.expect(Call::LineTo(Point::new(50.0, 71.0)), false);
    receiver.expect(Call::ConicTo(Point::new(50.0, 60.0), Point::new(51.0, 60.0), kSqrt2Over2), false);
    // RetiresOnSaturation keeps identical calls from matching each other
    receiver.expect(Call::Close, false);
  }

  source.dispatch(&mut receiver);
  receiver.verify();
}

#[test]
fn dashed_line_path_source() {
  let source = DashedLinePathSource::new(Point::new(10.0, 10.0), Point::new(30.0, 10.0), 5.0, 5.0);

  expect_false!(source.is_convex());
  expect_eq!(source.get_fill_type(), FillType::kNonZero);
  expect_eq!(source.get_bounds(), Rect::make_ltrb(10.0, 10.0, 30.0, 10.0));

  let mut receiver = DlPathReceiverMock::default();

  {

    receiver.expect(Call::MoveTo(Point::new(10.0, 10.0), false), false);
    receiver.expect(Call::LineTo(Point::new(15.0, 10.0)), false);
    receiver.expect(Call::MoveTo(Point::new(20.0, 10.0), false), false);
    receiver.expect(Call::LineTo(Point::new(25.0, 10.0)), false);
  }

  source.dispatch(&mut receiver);
  receiver.verify();
}

#[test]
fn empty_dashed_line_path_source() {
  let source = DashedLinePathSource::new(Point::new(10.0, 10.0), Point::new(10.0, 10.0), 5.0, 5.0);

  expect_false!(source.is_convex());
  expect_eq!(source.get_fill_type(), FillType::kNonZero);
  expect_eq!(source.get_bounds(), Rect::make_ltrb(10.0, 10.0, 10.0, 10.0));

  let mut receiver = DlPathReceiverMock::default();

  {

    receiver.expect(Call::MoveTo(Point::new(10.0, 10.0), false), false);
    receiver.expect(Call::LineTo(Point::new(10.0, 10.0)), false);
  }

  source.dispatch(&mut receiver);
  receiver.verify();
}

#[test]
fn dashed_line_path_source_zero_off_gaps() {
  let source = DashedLinePathSource::new(Point::new(10.0, 10.0), Point::new(30.0, 10.0), 5.0, 0.0);

  expect_false!(source.is_convex());
  expect_eq!(source.get_fill_type(), FillType::kNonZero);
  expect_eq!(source.get_bounds(), Rect::make_ltrb(10.0, 10.0, 30.0, 10.0));

  let mut receiver = DlPathReceiverMock::default();

  {

    receiver.expect(Call::MoveTo(Point::new(10.0, 10.0), false), false);
    receiver.expect(Call::LineTo(Point::new(30.0, 10.0)), false);
  }

  source.dispatch(&mut receiver);
  receiver.verify();
}

#[test]
fn dashed_line_path_source_invalid_off_gaps() {
  let source = DashedLinePathSource::new(Point::new(10.0, 10.0), Point::new(30.0, 10.0), 5.0, -1.0);

  expect_false!(source.is_convex());
  expect_eq!(source.get_fill_type(), FillType::kNonZero);
  expect_eq!(source.get_bounds(), Rect::make_ltrb(10.0, 10.0, 30.0, 10.0));

  let mut receiver = DlPathReceiverMock::default();

  {

    receiver.expect(Call::MoveTo(Point::new(10.0, 10.0), false), false);
    receiver.expect(Call::LineTo(Point::new(30.0, 10.0)), false);
  }

  source.dispatch(&mut receiver);
  receiver.verify();
}

#[test]
fn dashed_line_path_source_invalid_on_region() {
  let source = DashedLinePathSource::new(Point::new(10.0, 10.0), Point::new(30.0, 10.0), -1.0, 5.0);

  expect_false!(source.is_convex());
  expect_eq!(source.get_fill_type(), FillType::kNonZero);
  expect_eq!(source.get_bounds(), Rect::make_ltrb(10.0, 10.0, 30.0, 10.0));

  let mut receiver = DlPathReceiverMock::default();

  {

    receiver.expect(Call::MoveTo(Point::new(10.0, 10.0), false), false);
    receiver.expect(Call::LineTo(Point::new(30.0, 10.0)), false);
  }

  source.dispatch(&mut receiver);
  receiver.verify();
}

#[test]
fn path_transformer_rect_source_test() {
  let mut matrix = Matrix::make_translate_scale(Vector3::new(2.0, 3.0, 1.0), Vector3::new(1.5, 4.25, 0.0));
  let mut rect = Rect::make_ltrb(10.0, 15.0, 20.0, 30.0);
  let source = RectPathSource::new(&rect);

  expect_true!(source.is_convex());
  expect_eq!(source.get_fill_type(), FillType::kNonZero);
  expect_eq!(source.get_bounds(), Rect::make_ltrb(10.0, 15.0, 20.0, 30.0));

  let mut mock_receiver = DlPathReceiverMock::default();

    mock_receiver.expect(Call::MoveTo(Point::new(21.5f32, 49.25f32), true), false);
    mock_receiver.expect(Call::LineTo(Point::new(41.5f32, 49.25f32)), false);
    mock_receiver.expect(Call::LineTo(Point::new(41.5f32, 94.25f32)), false);
    mock_receiver.expect(Call::LineTo(Point::new(21.5f32, 94.25f32)), false);
    mock_receiver.expect(Call::LineTo(Point::new(21.5f32, 49.25f32)), false);
    mock_receiver.expect(Call::Close, false);
  {
    let mut receiver = PathTransformer::new(&mut mock_receiver, &matrix);

  source.dispatch(&mut receiver);
  }
  mock_receiver.verify();
}

#[test]
fn path_transformer_all_segments_test() {
  let mut matrix = Matrix::make_translate_scale(Vector3::new(2.0, 3.0, 1.0), Vector3::new(1.5, 4.25, 0.0));

  let mut mock_receiver = DlPathReceiverMock::default();

    mock_receiver.expect(Call::MoveTo(Point::new(21.5f32, 49.25f32), false), false);
    mock_receiver.expect(Call::LineTo(Point::new(41.5f32, 49.25f32)), false);

    mock_receiver.expect(Call::MoveTo(Point::new(221.5f32, 349.25f32), true), false);
    mock_receiver.expect(Call::QuadTo(Point::new(241.5f32, 349.25f32), Point::new(241.5f32, 394.25f32)), false);
    mock_receiver.expect(Call::ConicTo(Point::new(237.5f32, 409.25f32), Point::new(231.5f32, 409.25f32), 5.0), true);
    mock_receiver.expect(Call::ConicTo(Point::new(225.5f32, 409.25f32), Point::new(221.5f32, 394.25f32), 6.0), false);
    mock_receiver.expect(Call::CubicTo(Point::new(211.5f32, 379.25f32), Point::new(211.5f32, 364.25f32), Point::new(221.5f32, 349.25f32)), false);
    mock_receiver.expect(Call::Close, false);
  {
    let mut receiver = PathTransformer::new(&mut mock_receiver, &matrix);

  receiver.move_to(&Point::new(10.0, 15.0), false);
  receiver.line_to(&Point::new(20.0, 15.0));

  receiver.move_to(&Point::new(110.0, 115.0), true);
  receiver.quad_to(&Point::new(120.0, 115.0), &Point::new(120.0, 130.0));
  expect_true!(receiver.conic_to(&Point::new(118.0, 135.0), &Point::new(115.0, 135.0), 5.0));
  expect_false!(receiver.conic_to(&Point::new(112.0, 135.0), &Point::new(110.0, 130.0), 6.0));
  receiver.cubic_to(&Point::new(105.0, 125.0), &Point::new(105.0, 120.0), &Point::new(110.0, 115.0));
  receiver.close();
  }
  mock_receiver.verify();
}

// flutter/display_list/testing/dl_test_mock_path_receiver.h, as the tests
// above use it: a gmock StrictMock in a Sequence. Each expectation must be
// met by the next call, in order, with arguments equal to it (gmock's
// default matcher is `==`); ConicTo returns the value given with
// `.WillOnce(Return(...))` (false by default); `verify` fails when an
// expectation is left unmet, as the mock's destructor would.

#[derive(Clone, Copy, Debug, PartialEq)]
enum Call {
  MoveTo(Point, bool),
  LineTo(Point),
  QuadTo(Point, Point),
  ConicTo(Point, Point, Scalar),
  CubicTo(Point, Point, Point),
  Close,
}

#[derive(Default)]
struct DlPathReceiverMock {
  expected: Vec<(Call, bool)>,
  next: usize,
}

impl DlPathReceiverMock {
  fn expect(&mut self, call: Call, ret: bool) {
    self.expected.push((call, ret));
  }

  fn called(&mut self, call: Call) -> bool {
    let Some(&(expected, ret)) = self.expected.get(self.next) else {
      panic!("Uninteresting mock function call: {call:?}");
    };
    assert_eq!(call, expected, "unexpected mock function call {}", self.next);
    self.next += 1;
    ret
  }

  fn verify(&self) {
    assert_eq!(self.next, self.expected.len(), "unsatisfied expectations: {:?}", &self.expected[self.next..]);
  }
}

impl PathReceiver for DlPathReceiverMock {
  fn move_to(&mut self, p2: &Point, will_be_closed: bool) {
    self.called(Call::MoveTo(*p2, will_be_closed));
  }
  fn line_to(&mut self, p2: &Point) {
    self.called(Call::LineTo(*p2));
  }
  fn quad_to(&mut self, cp: &Point, p2: &Point) {
    self.called(Call::QuadTo(*cp, *p2));
  }
  fn conic_to(&mut self, cp: &Point, p2: &Point, weight: Scalar) -> bool {
    self.called(Call::ConicTo(*cp, *p2, weight))
  }
  fn cubic_to(&mut self, cp1: &Point, cp2: &Point, p2: &Point) {
    self.called(Call::CubicTo(*cp1, *cp2, *p2));
  }
  fn close(&mut self) {
    self.called(Call::Close);
  }
}
