// DVModifier's gesture helpers below onTap and onLongPress: a double tap,
// the four swipes, and onGesture for a custom drag, pinch or rotate. An
// application names the gesture; this builds the detector. Each swipe is
// also offered to a screen reader as the matching scroll action, so no
// gesture is touch-only.
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// A custom gesture: one finger drags, two pinch and rotate. [onUpdate]'s
/// details carry the focal point, its delta, the scale and the rotation.
class DVGesture {
  const DVGesture({this.onStart, this.onUpdate, this.onEnd});

  final GestureScaleStartCallback? onStart;
  final GestureScaleUpdateCallback? onUpdate;
  final GestureScaleEndCallback? onEnd;
}

/// How fast a fling must be, in logical pixels a second, to be a swipe. A
/// slow drag is someone reading, not swiping.
const double dvSwipeVelocity = 300;

/// The gestures one modifier carries, beyond tap and long press.
class DVGestureSet {
  const DVGestureSet({this.doubleTap, this.swipeLeft, this.swipeRight, this.swipeUp, this.swipeDown, this.custom});

  final VoidCallback? doubleTap;
  final VoidCallback? swipeLeft;
  final VoidCallback? swipeRight;
  final VoidCallback? swipeUp;
  final VoidCallback? swipeDown;
  final DVGesture? custom;

  DVGestureSet copyWith({VoidCallback? doubleTap, VoidCallback? swipeLeft, VoidCallback? swipeRight, VoidCallback? swipeUp, VoidCallback? swipeDown, DVGesture? custom}) =>
      DVGestureSet(
        doubleTap: doubleTap ?? this.doubleTap,
        swipeLeft: swipeLeft ?? this.swipeLeft,
        swipeRight: swipeRight ?? this.swipeRight,
        swipeUp: swipeUp ?? this.swipeUp,
        swipeDown: swipeDown ?? this.swipeDown,
        custom: custom ?? this.custom,
      );

  /// [other]'s gestures over these, as DVModifier.merge does for every value.
  DVGestureSet merge(DVGestureSet? other) => other == null
      ? this
      : copyWith(
          doubleTap: other.doubleTap,
          swipeLeft: other.swipeLeft,
          swipeRight: other.swipeRight,
          swipeUp: other.swipeUp,
          swipeDown: other.swipeDown,
          custom: other.custom,
        );

  bool get _horizontal => swipeLeft != null || swipeRight != null;
  bool get _vertical => swipeUp != null || swipeDown != null;

  /// [child] with these gestures, and the swipes as semantics actions.
  Widget wrap(Widget child) {
    final DVGesture? gesture = custom;
    // A scale recognizer already follows one-finger drags, and Flutter
    // refuses a scale and a pan on one detector, so the custom gesture is
    // scale alone; the swipes are drag recognizers beside it.
    Widget result = GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onDoubleTap: doubleTap,
      onHorizontalDragEnd: _horizontal && gesture == null
          ? (DragEndDetails details) {
              final double velocity = details.primaryVelocity ?? 0;
              if (velocity <= -dvSwipeVelocity) swipeLeft?.call();
              if (velocity >= dvSwipeVelocity) swipeRight?.call();
            }
          : null,
      onVerticalDragEnd: _vertical && gesture == null
          ? (DragEndDetails details) {
              final double velocity = details.primaryVelocity ?? 0;
              if (velocity <= -dvSwipeVelocity) swipeUp?.call();
              if (velocity >= dvSwipeVelocity) swipeDown?.call();
            }
          : null,
      onScaleStart: gesture?.onStart,
      onScaleUpdate: gesture?.onUpdate,
      onScaleEnd: gesture == null
          ? null
          : (ScaleEndDetails details) {
              gesture.onEnd?.call(details);
              // With a custom gesture the swipes are read from its end, since
              // the scale recognizer has the drag.
              final Offset velocity = details.velocity.pixelsPerSecond;
              if (velocity.dx.abs() >= velocity.dy.abs()) {
                if (velocity.dx <= -dvSwipeVelocity) swipeLeft?.call();
                if (velocity.dx >= dvSwipeVelocity) swipeRight?.call();
              } else {
                if (velocity.dy <= -dvSwipeVelocity) swipeUp?.call();
                if (velocity.dy >= dvSwipeVelocity) swipeDown?.call();
              }
            },
      child: child,
    );
    return result;
  }

  /// [child] offering the swipes to a screen reader. Applied outside the
  /// control's label, which excludes what is beneath it, so the name and the
  /// actions are one node. Swiping up moves content up, which a screen
  /// reader calls scrolling up; the same for the other three.
  Widget announce(Widget child) => _horizontal || _vertical
      ? Semantics(onScrollUp: swipeUp, onScrollDown: swipeDown, onScrollLeft: swipeLeft, onScrollRight: swipeRight, child: child)
      : child;
}
