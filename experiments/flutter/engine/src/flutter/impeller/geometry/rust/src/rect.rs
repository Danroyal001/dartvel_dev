// flutter/impeller/geometry/rect.h (rect.cc is empty)
//
// `TRect<T>` keeps upstream's template: `Rect` (float), `IRect32` (int32_t)
// and `IRect64`/`IRect` (int64_t). Methods upstream enables only for floating
// point types (`IsFinite`, `Make`, the rounding factories) or that only
// compile for `Scalar` (the transforms) are in `impl TRect<Scalar>`.

use std::fmt;

use crate::cxx::{self, Kind, Num, conv};
use crate::matrix::Matrix;
use crate::point::{Point, TPoint};
use crate::saturated::{self, SaturatedArith, SaturatedCast};
use crate::scalar::Scalar;
use crate::size::{Size, TSize};
use crate::vector::Vector3;

/// The element types a `TRect` is instantiated with.
pub trait RectNum: Num + SaturatedArith {}
impl RectNum for f32 {}
impl RectNum for f64 {}
impl RectNum for i32 {}
impl RectNum for i64 {}

/// Templated struct for holding an axis-aligned rectangle.
///
/// Rectangles are defined as 4 axis-aligned edges that might contain space.
/// They can be viewed as 2 X coordinates that define the left and right edges
/// and 2 Y coordinates that define the top and bottom edges; or they can be
/// viewed as an origin and horizontal and vertical dimensions (width and
/// height). When the left and right edges are equal or reversed (right <=
/// left) or the top and bottom edges are equal or reversed (bottom <= top),
/// the rectangle is considered empty.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct TRect<T> {
    left_: T,
    top_: T,
    right_: T,
    bottom_: T,
}

pub type Rect = TRect<Scalar>;
pub type IRect32 = TRect<i32>;
pub type IRect64 = TRect<i64>;
pub type IRect = IRect64;

/// `C++ a <cmp> b` for two arithmetic types: both are converted to their
/// common type first.
fn ge<A: Num, B: Num>(a: A, b: B) -> bool {
    match Kind::common(A::KIND, B::KIND) {
        Kind::F64 => a.to_f64() >= b.to_f64(),
        Kind::F32 => a.to_f32() >= b.to_f32(),
        k => k.wrap(a.to_i128()) >= k.wrap(b.to_i128()),
    }
}

impl<T: RectNum> TRect<T> {
    const fn raw(left: T, top: T, right: T, bottom: T) -> Self {
        TRect { left_: left, top_: top, right_: right, bottom_: bottom }
    }

    pub const fn make_ltrb(left: T, top: T, right: T, bottom: T) -> Self {
        TRect::raw(left, top, right, bottom)
    }

    pub fn make_xywh(x: T, y: T, width: T, height: T) -> Self {
        TRect::raw(x, y, saturated::add(x, width), saturated::add(y, height))
    }

    pub fn make_wh(width: T, height: T) -> Self {
        TRect::raw(T::zero(), T::zero(), width, height)
    }

    pub fn make_origin_size(origin: &TPoint<T>, size: &TSize<T>) -> Self {
        TRect::make_xywh(origin.x, origin.y, size.width, size.height)
    }

    pub fn make_size<U: Num>(size: &TSize<U>) -> Self {
        TRect::raw(T::from_f64(0.0), T::from_f64(0.0), conv(size.width), conv(size.height))
    }

    pub fn make_circle_bounds(center: &TPoint<T>, radius: T) -> Self {
        TRect::make_ltrb(
            center.x.sub(radius),
            center.y.sub(radius),
            center.x.add(radius),
            center.y.add(radius),
        )
    }

    pub fn make_ellipse_bounds(center: &TPoint<T>, radii: &TSize<T>) -> Self {
        TRect::make_ltrb(
            center.x.sub(radii.width),
            center.y.sub(radii.height),
            center.x.add(radii.width),
            center.y.add(radii.height),
        )
    }

    /// `MakeEllipseBounds(const TPoint<Type>& center, const TPoint<Type>& radii)`.
    pub fn make_ellipse_bounds_point(center: &TPoint<T>, radii: &TPoint<T>) -> Self {
        TRect::make_ltrb(
            center.x.sub(radii.x),
            center.y.sub(radii.y),
            center.x.add(radii.x),
            center.y.add(radii.y),
        )
    }

    /// `MakePointBounds(first, last)`.
    pub fn make_point_bounds(points: &[TPoint<T>]) -> Option<Self> {
        let first = points.first()?;
        let mut left = first.x;
        let mut top = first.y;
        let mut right = first.x;
        let mut bottom = first.y;
        for it in &points[1..] {
            left = cxx::min(left, it.x);
            top = cxx::min(top, it.y);
            right = cxx::max(right, it.x);
            bottom = cxx::max(bottom, it.y);
        }
        Some(TRect::make_ltrb(left, top, right, bottom))
    }

    pub fn make_maximum() -> Self {
        TRect::make_ltrb(T::LOWEST, T::LOWEST, T::MAX, T::MAX)
    }

    pub fn scale(&self, scale: T) -> Self {
        TRect::raw(
            self.left_.mul(scale),
            self.top_.mul(scale),
            self.right_.mul(scale),
            self.bottom_.mul(scale),
        )
    }

    pub fn scale_xy(&self, scale_x: T, scale_y: T) -> Self {
        TRect::raw(
            self.left_.mul(scale_x),
            self.top_.mul(scale_y),
            self.right_.mul(scale_x),
            self.bottom_.mul(scale_y),
        )
    }

    pub fn scale_point(&self, scale: TPoint<T>) -> Self {
        self.scale_xy(scale.x, scale.y)
    }

    pub fn scale_size(&self, scale: TSize<T>) -> Self {
        self.scale_xy(scale.width, scale.height)
    }

    /// Returns true iff the provided point |p| is inside the half-open
    /// interior of this rectangle.
    pub fn contains(&self, p: &TPoint<T>) -> bool {
        // `&` for `&&`, as in `contains_rect`.
        !self.is_empty()
            & (p.x >= self.left_)
            & (p.y >= self.top_)
            & (p.x < self.right_)
            & (p.y < self.bottom_)
    }

    /// Returns true iff the provided point |p| is inside the closed-range
    /// interior of this rectangle.
    pub fn contains_inclusive(&self, p: &TPoint<T>) -> bool {
        !self.is_empty()
            && p.x >= self.left_
            && p.y >= self.top_
            && p.x <= self.right_
            && p.y <= self.bottom_
    }

    /// Returns true iff this rectangle is not empty and it also contains
    /// every point considered inside the provided rectangle |o|.
    pub fn contains_rect(&self, o: &Self) -> bool {
        // Upstream's `&&`/`||` chain evaluated with `&`/`|`: no operand has
        // side effects, and on unpredictable data a branch per comparison
        // costs more than computing them all.
        !self.is_empty()
            & (o.is_empty()
                | ((o.left_ >= self.left_)
                    & (o.top_ >= self.top_)
                    & (o.right_ <= self.right_)
                    & (o.bottom_ <= self.bottom_)))
    }

    pub fn is_empty(&self) -> bool {
        // `&` for `&&`, as in `contains_rect`.
        !((self.left_ < self.right_) & (self.top_ < self.bottom_))
    }

    pub fn is_square(&self) -> bool {
        // empty rectangles can technically be "square", but would be
        // misleading to most callers. Using |IsEmpty| also prevents
        // "non-numbers" from being considered square.
        !self.is_empty() && self.right_.sub(self.left_) == self.bottom_.sub(self.top_)
    }

    pub fn is_maximum(&self) -> bool {
        *self == TRect::make_maximum()
    }

    pub fn get_origin(&self) -> TPoint<T> {
        TPoint::new(self.left_, self.top_)
    }

    pub fn get_size(&self) -> TSize<T> {
        TSize::new(self.get_width(), self.get_height())
    }

    pub fn get_x(&self) -> T {
        self.left_
    }

    pub fn get_y(&self) -> T {
        self.top_
    }

    pub fn get_width(&self) -> T {
        saturated::sub(self.right_, self.left_)
    }

    pub fn get_height(&self) -> T {
        saturated::sub(self.bottom_, self.top_)
    }

    pub fn get_left(&self) -> T {
        self.left_
    }

    pub fn get_top(&self) -> T {
        self.top_
    }

    pub fn get_right(&self) -> T {
        self.right_
    }

    pub fn get_bottom(&self) -> T {
        self.bottom_
    }

    pub fn get_left_top(&self) -> TPoint<T> {
        TPoint::new(self.left_, self.top_)
    }

    pub fn get_right_top(&self) -> TPoint<T> {
        TPoint::new(self.right_, self.top_)
    }

    pub fn get_left_bottom(&self) -> TPoint<T> {
        TPoint::new(self.left_, self.bottom_)
    }

    pub fn get_right_bottom(&self) -> TPoint<T> {
        TPoint::new(self.right_, self.bottom_)
    }

    /// Get the area of the rectangle, equivalent to |GetSize().Area()|
    pub fn area(&self) -> T {
        // TODO(141710): Use saturated math to avoid overflow.
        if self.is_empty() {
            T::zero()
        } else {
            self.right_.sub(self.left_).mul(self.bottom_.sub(self.top_))
        }
    }

    /// Get the center point as a |Point|.
    pub fn get_center(&self) -> Point {
        Point::new(
            saturated::average_scalar(self.left_, self.right_),
            saturated::average_scalar(self.top_, self.bottom_),
        )
    }

    pub fn get_ltrb(&self) -> [T; 4] {
        [self.left_, self.top_, self.right_, self.bottom_]
    }

    /// Get the x, y coordinates of the origin and the width and height of
    /// the rectangle in an array.
    pub fn get_xywh(&self) -> [T; 4] {
        [self.left_, self.top_, self.get_width(), self.get_height()]
    }

    /// Get a version of this rectangle that has a non-negative size.
    pub fn get_positive(&self) -> Self {
        if !self.is_empty() {
            return *self;
        }
        TRect::raw(
            cxx::min(self.left_, self.right_),
            cxx::min(self.top_, self.bottom_),
            cxx::max(self.left_, self.right_),
            cxx::max(self.top_, self.bottom_),
        )
    }

    /// Get the points that represent the 4 corners of this rectangle in a Z
    /// order that is compatible with triangle strips or a set of all zero
    /// points if the rectangle is empty. The order is: Top left, top right,
    /// bottom left, bottom right.
    pub fn get_points(&self) -> [TPoint<T>; 4] {
        if self.is_empty() {
            return [TPoint::default(); 4];
        }
        [
            TPoint::new(self.left_, self.top_),
            TPoint::new(self.right_, self.top_),
            TPoint::new(self.left_, self.bottom_),
            TPoint::new(self.right_, self.bottom_),
        ]
    }

    /// Constructs a Matrix that will map all points in the coordinate space
    /// of the rectangle into a new normalized coordinate space where the
    /// upper left corner of the rectangle maps to (0, 0) and the lower right
    /// corner of the rectangle maps to (1, 1).
    ///
    /// Empty and non-finite rectangles will return a zero-scaling transform
    /// that maps all points to (0, 0).
    #[rustfmt::skip]
    pub fn get_normalizing_transform(&self) -> Matrix {
        if !self.is_empty() {
            // `1.0 / GetWidth()` divides in double and narrows. For a float
            // rect that is one division rounded twice, which equals the float
            // division (53 >= 2*24+2 bits); an integer rect keeps the double.
            let (sx, sy): (Scalar, Scalar) = if T::KIND == cxx::Kind::F32 {
                (1.0 / self.get_width().to_f32(), 1.0 / self.get_height().to_f32())
            } else {
                (
                    (1.0 / self.get_width().to_f64()) as Scalar,
                    (1.0 / self.get_height().to_f64()) as Scalar,
                )
            };
            let tx: Scalar = self.left_.to_f32() * -sx;
            let ty: Scalar = self.top_.to_f32() * -sy;

            // Exclude NaN and infinities and either scale underflowing to
            // zero
            if sx != 0.0
                && sy != 0.0
                // Upstream multiplies in double; 0 times finite floats is a
                // zero and any infinity or NaN makes a NaN in either width.
                && 0.0 * sx * sy * tx * ty == 0.0
            {
                return Matrix::new(sx,  0.0, 0.0, 0.0,
                                   0.0, sy,  0.0, 0.0,
                                   0.0, 0.0, 1.0, 0.0,
                                   tx,  ty,  0.0, 1.0);
            }
        }

        // Map all coordinates to the origin.
        Matrix::make_scale(Vector3::new(0.0, 0.0, 1.0))
    }

    /// Returns the union of this rectangle and the given rectangle, or
    /// whichever one is not empty.
    pub fn union(&self, o: &Self) -> Self {
        // Upstream returns `o` if this is empty, else this if `o` is empty,
        // else the min/max bounds. Chosen field by field, so that the choice
        // is a select rather than a branch on unpredictable data.
        let (self_empty, o_empty) = (self.is_empty(), o.is_empty());
        let pick = |mine: T, theirs: T, both: T| {
            if self_empty {
                theirs
            } else if o_empty {
                mine
            } else {
                both
            }
        };
        TRect::raw(
            pick(self.left_, o.left_, cxx::min(self.left_, o.left_)),
            pick(self.top_, o.top_, cxx::min(self.top_, o.top_)),
            pick(self.right_, o.right_, cxx::max(self.right_, o.right_)),
            pick(self.bottom_, o.bottom_, cxx::max(self.bottom_, o.bottom_)),
        )
    }

    pub fn intersection(&self, o: &Self) -> Option<Self> {
        if self.intersects_with_rect(o) {
            Some(TRect::raw(
                cxx::max(self.left_, o.left_),
                cxx::max(self.top_, o.top_),
                cxx::min(self.right_, o.right_),
                cxx::min(self.bottom_, o.bottom_),
            ))
        } else {
            None
        }
    }

    pub fn intersection_or_empty(&self, o: &Self) -> Self {
        self.intersection(o).unwrap_or_default()
    }

    pub fn intersects_with_rect(&self, o: &Self) -> bool {
        !self.is_empty()
            && !o.is_empty()
            && self.left_ < o.right_
            && self.top_ < o.bottom_
            && self.right_ > o.left_
            && self.bottom_ > o.top_
    }

    /// Returns the new boundary rectangle that would result from this
    /// rectangle being cut out by the specified rectangle.
    pub fn cutout(&self, o: &Self) -> Option<Self> {
        if self.is_empty() {
            // This test isn't just a short-circuit, it also prevents the
            // concise math below from returning the wrong answer on empty
            // rects. Once we know that this rectangle is not empty, the math
            // below can only succeed in computing a value if o is also
            // non-empty and non-overlapping.
            return None;
        }
        let [a_left, a_top, a_right, a_bottom] = self.get_ltrb(); // Source rect.
        let [b_left, b_top, b_right, b_bottom] = o.get_ltrb(); // Cutout.
        if b_left <= a_left && b_right >= a_right {
            if b_top <= a_top && b_bottom >= a_bottom {
                // Full cutout.
                return None;
            }
            if b_top <= a_top && b_bottom > a_top {
                // Cuts off the top.
                return Some(TRect::make_ltrb(a_left, b_bottom, a_right, a_bottom));
            }
            if b_bottom >= a_bottom && b_top < a_bottom {
                // Cuts off the bottom.
                return Some(TRect::make_ltrb(a_left, a_top, a_right, b_top));
            }
        }
        if b_top <= a_top && b_bottom >= a_bottom {
            if b_left <= a_left && b_right > a_left {
                // Cuts off the left.
                return Some(TRect::make_ltrb(b_right, a_top, a_right, a_bottom));
            }
            if b_right >= a_right && b_left < a_right {
                // Cuts off the right.
                return Some(TRect::make_ltrb(a_left, a_top, b_left, a_bottom));
            }
        }

        Some(*self)
    }

    pub fn cutout_or_empty(&self, o: &Self) -> Self {
        self.cutout(o).unwrap_or_default()
    }

    /// Returns a new rectangle translated by the given offset.
    pub fn shift(&self, dx: T, dy: T) -> Self {
        TRect::raw(
            saturated::add(self.left_, dx),
            saturated::add(self.top_, dy),
            saturated::add(self.right_, dx),
            saturated::add(self.bottom_, dy),
        )
    }

    pub fn shift_point(&self, offset: TPoint<T>) -> Self {
        self.shift(offset.x, offset.y)
    }

    /// Returns a rectangle with expanded edges. Negative expansion results
    /// in shrinking.
    pub fn expand_ltrb(&self, left: T, top: T, right: T, bottom: T) -> Self {
        TRect::raw(
            saturated::sub(self.left_, left),
            saturated::sub(self.top_, top),
            saturated::add(self.right_, right),
            saturated::add(self.bottom_, bottom),
        )
    }

    pub fn expand(&self, amount: T) -> Self {
        TRect::raw(
            saturated::sub(self.left_, amount),
            saturated::sub(self.top_, amount),
            saturated::add(self.right_, amount),
            saturated::add(self.bottom_, amount),
        )
    }

    pub fn expand_xy(&self, horizontal_amount: T, vertical_amount: T) -> Self {
        TRect::raw(
            saturated::sub(self.left_, horizontal_amount),
            saturated::sub(self.top_, vertical_amount),
            saturated::add(self.right_, horizontal_amount),
            saturated::add(self.bottom_, vertical_amount),
        )
    }

    pub fn expand_point(&self, amount: TPoint<T>) -> Self {
        self.expand_xy(amount.x, amount.y)
    }

    pub fn expand_size(&self, amount: TSize<T>) -> Self {
        self.expand_xy(amount.width, amount.height)
    }

    /// Returns a new rectangle that represents the projection of the source
    /// rectangle onto this rectangle. In other words, the source rectangle
    /// is redefined in terms of the coordinate space of this rectangle.
    pub fn project(&self, source: TRect<T>) -> Self {
        if self.is_empty() {
            return TRect::default();
        }
        source.shift(self.left_.neg(), self.top_.neg()).scale_xy(
            T::from_f64(1.0 / self.get_width().to_f32() as f64),
            T::from_f64(1.0 / self.get_height().to_f32() as f64),
        )
    }

    /// `RoundOut(const TRect<U>&)`: floor the left and top, ceil the right
    /// and bottom, then `saturated::Cast` to `Type`.
    pub fn round_out<U: RectNum + SaturatedCast<T>>(r: &TRect<U>) -> Self {
        TRect::make_ltrb(
            saturated::cast(r.get_left().floor_c()),
            saturated::cast(r.get_top().floor_c()),
            saturated::cast(r.get_right().ceil_c()),
            saturated::cast(r.get_bottom().ceil_c()),
        )
    }

    pub fn round_in<U: RectNum + SaturatedCast<T>>(r: &TRect<U>) -> Self {
        TRect::make_ltrb(
            saturated::cast(r.get_left().ceil_c()),
            saturated::cast(r.get_top().ceil_c()),
            saturated::cast(r.get_right().floor_c()),
            saturated::cast(r.get_bottom().floor_c()),
        )
    }

    pub fn round<U: RectNum + SaturatedCast<T>>(r: &TRect<U>) -> Self {
        TRect::make_ltrb(
            saturated::cast(r.get_left().round_c()),
            saturated::cast(r.get_top().round_c()),
            saturated::cast(r.get_right().round_c()),
            saturated::cast(r.get_bottom().round_c()),
        )
    }

    /// `static Union(const TRect& a, const std::optional<TRect> b)`.
    pub fn union_opt_b(a: &Self, b: Option<Self>) -> Self {
        match b {
            Some(b) => a.union(&b),
            None => *a,
        }
    }

    pub fn union_opt_a(a: Option<Self>, b: &Self) -> Self {
        match a {
            Some(a) => a.union(b),
            None => *b,
        }
    }

    pub fn union_opt(a: Option<Self>, b: Option<Self>) -> Option<Self> {
        match a {
            Some(a) => Some(TRect::union_opt_b(&a, b)),
            None => b,
        }
    }

    pub fn intersection_opt_b(a: &Self, b: Option<Self>) -> Option<Self> {
        match b {
            Some(b) => a.intersection(&b),
            None => Some(*a),
        }
    }

    pub fn intersection_opt_a(a: Option<Self>, b: &Self) -> Option<Self> {
        match a {
            Some(a) => a.intersection(b),
            None => Some(*b),
        }
    }

    pub fn intersection_opt(a: Option<Self>, b: Option<Self>) -> Option<Self> {
        match a {
            Some(a) => TRect::intersection_opt_b(&a, b),
            None => b,
        }
    }
}

impl<T: RectNum> TRect<T>
where
    T: Num,
{
    /// `Contains(const TRect<U>& o)` for a floating point `Type`: the edges
    /// are compared after the usual arithmetic conversions.
    pub fn contains_rect_of<U: RectNum>(&self, o: &TRect<U>) -> bool {
        debug_assert!(T::KIND.is_float());
        !self.is_empty()
            && (o.is_empty()
                || (ge(o.get_left(), self.left_)
                    && ge(o.get_top(), self.top_)
                    && ge(self.right_, o.get_right())
                    && ge(self.bottom_, o.get_bottom())))
    }

    /// `Make(const TRect<U>& rect)` for a floating point `Type`.
    pub fn make<U: RectNum>(rect: &TRect<U>) -> Self {
        TRect::make_ltrb(
            conv(rect.get_left()),
            conv(rect.get_top()),
            conv(rect.get_right()),
            conv(rect.get_bottom()),
        )
    }

    /// Returns true if all of the fields of this floating point rectangle
    /// are finite.
    pub fn is_finite(&self) -> bool {
        self.left_.is_finite_t()
            && self.top_.is_finite_t()
            && self.right_.is_finite_t()
            && self.bottom_.is_finite_t()
    }
}

const kMinimumHomogenous: Scalar = 1.0 / (1 << 14) as Scalar;

impl TRect<Scalar> {
    #[inline]
    /// Creates a new bounding box that contains this transformed rectangle.
    pub fn get_transformed_points(&self, transform: &Matrix) -> [Point; 4] {
        let mut points = self.get_points();
        for p in points.iter_mut() {
            *p = *transform * *p;
        }
        points
    }

    #[inline]
    /// Creates a new bounding box that contains this transformed rectangle,
    /// clipped against the near clipping plane if necessary.
    pub fn transform_and_clip_bounds(&self, transform: &Matrix) -> Rect {
        if !transform.has_perspective_2d() {
            return self.transform_bounds(transform);
        }

        if self.is_empty() {
            return Rect::default();
        }

        let ul = transform.transform_homogenous(&Point::new(self.left_, self.top_));
        let ur = transform.transform_homogenous(&Point::new(self.right_, self.top_));
        let ll = transform.transform_homogenous(&Point::new(self.left_, self.bottom_));
        let lr = transform.transform_homogenous(&Point::new(self.right_, self.bottom_));

        // It can probably be proven that we only ever have 5 points at most
        // which happens when only 1 corner is clipped and we get 2 points
        // in return for it as we interpolate against its neighbors.
        let mut points = [Point::default(); 8];
        let mut index = 0;

        // Process (clip and interpolate) each point against its 2 neighbors:
        // left, pt, right
        index = clip_and_insert(&mut points, index, &ll, &ul, &ur);
        index = clip_and_insert(&mut points, index, &ul, &ur, &lr);
        index = clip_and_insert(&mut points, index, &ur, &lr, &ll);
        index = clip_and_insert(&mut points, index, &lr, &ll, &ul);

        let bounds = TRect::make_point_bounds(&points[..index]);
        bounds.unwrap_or_default()
    }

    #[inline]
    /// Creates a new bounding box that contains this transformed rectangle.
    pub fn transform_bounds(&self, transform: &Matrix) -> Rect {
        if self.is_empty() {
            return Rect::default();
        }
        let points = self.get_transformed_points(transform);
        match TRect::make_point_bounds(&points) {
            Some(bounds) => bounds,
            None => fml::fml_unreachable_at!("flutter/impeller/geometry/rect.h", 515),
        }
    }


    #[inline]
    /// Returns a new rectangle that represents the projection of the source
    /// rectangle onto this rectangle, expanded so that, once transformed, it
    /// is at least the given size.
    pub fn expand_to_min_transformed_size(
        &self,
        min_transformed_size: Size,
        transform: &Matrix,
    ) -> Option<Rect> {
        fml::fml_dcheck_at!(
            "flutter/impeller/geometry/rect.h",
            708,
            "!transform.HasPerspective2D()",
            !transform.has_perspective_2d()
        );
        let transform_scaling = transform.get_basis_scale_xy();
        if transform_scaling.x == 0.0 || transform_scaling.y == 0.0 {
            return None;
        }
        let min_local_size = Size::new(
            min_transformed_size.width / transform_scaling.x,
            min_transformed_size.height / transform_scaling.y,
        );
        if !min_local_size.is_finite() {
            return None;
        }
        let current_size = self.get_size();
        if current_size.width >= min_local_size.width
            && current_size.height >= min_local_size.height
        {
            return Some(*self);
        }
        let expanded_size = current_size.max(&min_local_size);
        Some(Rect::make_ellipse_bounds_point(
            &self.get_center(),
            &Point::new(expanded_size.width * 0.5, expanded_size.height * 0.5),
        ))
    }
}

fn clip_and_insert(
    clipped: &mut [Point; 8],
    mut index: usize,
    left: &Vector3,
    p: &Vector3,
    right: &Vector3,
) -> usize {
    if p.z >= kMinimumHomogenous {
        // At most two points per corner of four: a write index is at most 7,
        // and the mask lets the compiler drop the bounds check.
        clipped[index & 7] = Point::new(p.x / p.z, p.y / p.z);
        index += 1;
    } else {
        index = interpolate_and_insert(clipped, index, p, left);
        index = interpolate_and_insert(clipped, index, p, right);
    }
    index
}

fn interpolate_and_insert(
    clipped: &mut [Point; 8],
    mut index: usize,
    p: &Vector3,
    neighbor: &Vector3,
) -> usize {
    if neighbor.z >= kMinimumHomogenous {
        let t = (kMinimumHomogenous - p.z) / (neighbor.z - p.z);
        clipped[index & 7] = Point::new(
            ((1.0 - t) * p.x + t * neighbor.x) / kMinimumHomogenous,
            ((1.0 - t) * p.y + t * neighbor.y) / kMinimumHomogenous,
        );
        index += 1;
    }
    index
}

impl<T: RectNum> fmt::Display for TRect<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "({} => {})", self.get_left_top(), self.get_right_bottom())
    }
}
