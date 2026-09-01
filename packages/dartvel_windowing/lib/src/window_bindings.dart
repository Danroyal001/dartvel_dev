part of '../dartvel_windowing.dart';

/// What an application asked for when it opened a window.
///
/// `DVWindow` records what a window *is* — its route, kind, presentation and
/// degradation — and not what was requested of the platform, so the size and
/// title arrive with the binding call and are kept here until the surface for
/// that window is built.
@immutable
class DVWindowRequest {
  const DVWindowRequest({this.size, this.title, this.route});

  /// The size asked for, or null to let the platform choose.
  final Size? size;

  /// The title asked for, or null to fall back to the application name.
  final String? title;

  /// The route the window presents.
  final String? route;
}

/// Registers the desktop window bindings.
///
/// `DVWindowingCapability.detect` gates `multiWindow` on `window.open` being
/// registered rather than on the API being importable, so this call is what
/// makes `DV.Platform.Window.open` present a real window instead of degrading
/// to a page. Nothing else in Dartvel has to change.
class _DVWindowBindings {
  const _DVWindowBindings._();

  static final Map<String, DVWindowRequest> _requests =
      <String, DVWindowRequest>{};
  static int _sequence = 0;
  static bool _registered = false;

  /// Registers `window.open` and `window.close`.
  ///
  /// The handlers do not create the OS window. They allocate its identity and
  /// record what was asked for; the window itself is created by
  /// [DVWindowSurfaces] once a frame has rendered, because a window controller
  /// built before the engine is up ends the process rather than throwing.
  static void register() {
    if (_registered) return;
    _registered = true;

    DVNativeBridge.register('window.open', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      final id = 'dv-window-${++_sequence}';
      final width = map['width'];
      final height = map['height'];
      _requests[id] = DVWindowRequest(
        size: width is num && height is num
            ? Size(width.toDouble(), height.toDouble())
            : null,
        title: map['title'] as String?,
        route: map['route'] as String?,
      );
      return id;
    });

    // Enumeration is a read, so it needs no request bookkeeping. It is
    // registered here rather than in dartvel_flutter's Linux bindings because
    // the specification lists window.displays among the *desktop windowing*
    // bindings, and because a target with no windowing has nothing to enumerate.
    DVNativeBridge.register(
      'window.displays',
      (Object? _) => _DVLinuxDisplays.enumerate(),
    );

    DVNativeBridge.register('window.close', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      final id = map['id'];
      if (id is String) _requests.remove(id);
      return true;
    });
  }

  /// What was asked for when the window with [nativeId] was opened.
  static DVWindowRequest? requestFor(String? nativeId) =>
      nativeId == null ? null : _requests[nativeId];

  /// Unregisters the bindings and forgets every request. For tests, and for a
  /// target that tears the windowing layer down.
  static void reset() {
    DVNativeBridge.unregister('window.open');
    DVNativeBridge.unregister('window.close');
    DVNativeBridge.unregister('window.displays');
    _requests.clear();
    _sequence = 0;
    _registered = false;
  }
}
