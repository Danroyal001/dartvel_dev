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
    // A scrolling list inside claims every vertical drag, so a swipe over it
    // never reaches the drag recognizers above. A pull past its top is the
    // swipe down, past its end the swipe up.
    if (_vertical) result = _DVEdgeSwipes(onPastStart: swipeDown, onPastEnd: swipeUp, child: result);
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

/// How far a finger pulls a vertical list past its top or end, in logical
/// pixels, before that is a swipe rather than a nudge at the edge.
const double dvEdgeSwipeDistance = 48;

/// Calls [onPastStart] when a finger pulls a vertical scrolling list inside
/// [child] past its top, and [onPastEnd] past its end: once per drag, and
/// only for a drag that started at that edge (a list scrolled back to its
/// top by the same drag is a scroll, not a swipe).
class _DVEdgeSwipes extends StatefulWidget {
  const _DVEdgeSwipes({required this.child, this.onPastStart, this.onPastEnd});

  final Widget child;
  final VoidCallback? onPastStart;
  final VoidCallback? onPastEnd;

  @override
  State<_DVEdgeSwipes> createState() => _DVEdgeSwipesState();
}

class _DVEdgeSwipesState extends State<_DVEdgeSwipes> {
  double _pulled = 0;
  bool _fired = false;
  bool _atStart = false;
  bool _atEnd = false;

  bool _heard(ScrollNotification notification) {
    final ScrollMetrics metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    if (notification is ScrollStartNotification) {
      _pulled = 0;
      _fired = false;
      _atStart = metrics.pixels <= metrics.minScrollExtent;
      _atEnd = metrics.pixels >= metrics.maxScrollExtent;
    } else if (notification is OverscrollNotification && notification.dragDetails != null) {
      // Clamping physics (Android): the list stays put and reports the rest.
      _pull(notification.overscroll);
    } else if (notification is ScrollUpdateNotification && notification.dragDetails != null) {
      // Bouncing physics (iOS): the list moves past its edge.
      if (metrics.pixels < metrics.minScrollExtent) {
        _pulled = metrics.pixels - metrics.minScrollExtent;
        _check();
      } else if (metrics.pixels > metrics.maxScrollExtent) {
        _pulled = metrics.pixels - metrics.maxScrollExtent;
        _check();
      } else if ((notification.scrollDelta ?? 0) != 0) {
        // The drag scrolled the list: it is a scroll from here on.
        _atStart = false;
        _atEnd = false;
      }
    } else if (notification is ScrollEndNotification) {
      _pulled = 0;
    }
    return false;
  }

  void _pull(double overscroll) {
    // Negative is past the top, positive past the end; a change of direction
    // starts counting again.
    if (_pulled != 0 && overscroll.sign != _pulled.sign) _pulled = 0;
    _pulled += overscroll;
    _check();
  }

  void _check() {
    if (_fired) return;
    if (_pulled <= -dvEdgeSwipeDistance && _atStart) {
      _fired = true;
      widget.onPastStart?.call();
    } else if (_pulled >= dvEdgeSwipeDistance && _atEnd) {
      _fired = true;
      widget.onPastEnd?.call();
    }
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(onNotification: _heard, child: widget.child);
}
