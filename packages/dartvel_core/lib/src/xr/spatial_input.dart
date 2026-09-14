/// Spatial input: selection events, never where somebody is looking.
library dartvel.xr.input;

import '../scene3d/scene_math.dart';

/// Where an input came from.
enum DVSpatialInputSource { hand, controller, gaze, voice }

/// What an input does. A select is `.onTap()`; grab and release are
/// `.onGrab()` and `.onRelease()`.
enum DVSpatialInputAction { select, grab, release }

/// One input.
///
/// Either a ray the runtime picks along, or a node the platform already
/// resolved. Gaze and voice can only be the second: the platforms forbid
/// exposing raw eye-gaze, and this type cannot carry it, so no code path can
/// hand an application where somebody looked.
final class DVSpatialInputEvent {
  const DVSpatialInputEvent._(
      this.action, this.source, this.origin, this.direction, this.nodeId);

  /// A hand ray or controller ray, in the device's convention.
  factory DVSpatialInputEvent.ray(
    DVSpatialInputAction action,
    DVSpatialInputSource source, {
    required DVVec3 origin,
    required DVVec3 direction,
  }) {
    if (source == DVSpatialInputSource.gaze || source == DVSpatialInputSource.voice) {
      throw ArgumentError.value(source, 'source',
          'a ${source.name} input arrives as the node it selected, never as a ray');
    }
    if (!origin.isFinite || !direction.isFinite || direction.length == 0) {
      throw ArgumentError('a ray needs a finite origin and a non-zero direction');
    }
    return DVSpatialInputEvent._(action, source, origin, direction, null);
  }

  /// A node the platform resolved the input to.
  factory DVSpatialInputEvent.target(
    DVSpatialInputAction action,
    DVSpatialInputSource source,
    String nodeId,
  ) =>
      DVSpatialInputEvent._(action, source, null, null, nodeId);

  final DVSpatialInputAction action;
  final DVSpatialInputSource source;
  final DVVec3? origin;
  final DVVec3? direction;
  final String? nodeId;

  @override
  String toString() => 'DVSpatialInputEvent(${action.name}, ${source.name})';
}
