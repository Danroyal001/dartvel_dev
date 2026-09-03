// The only place that touches Flutter's windowing API, which is @internal,
// behind a feature flag, and master-channel only.
// ignore_for_file: invalid_use_of_internal_member
part of '../dartvel_windowing.dart';

/// Turns a Dartvel window into a real OS window.
class DVFlutterWindowSurfaceFactory implements DVWindowSurfaceFactory {
  const DVFlutterWindowSurfaceFactory();

  /// Enables Flutter's windowing feature for this application.
  ///
  /// The flag is a plain mutable `bool` the tool sets from
  /// `--dart-define=FLUTTER_ENABLED_FEATURE_FLAGS`, and it only injects that
  /// define on the master channel — `flutter config --enable-windowing`
  /// reports success on stable and changes nothing. Assigning it here means an
  /// application gets the same behaviour however it was built, and does not
  /// have to know the flag exists.
  static void enable() {
    isWindowingEnabled = true;
  }

  /// Used when a window is opened without a size.
  ///
  /// `DVWindowOptions.size` is optional, so the gap has to be filled
  /// somewhere. It is filled here, visibly, rather than by making the Dartvel
  /// option required: a projector window's real size comes from the display it
  /// is going to, which is a separate question from what a window defaults to.
  static const Size defaultSize = Size(1280, 720);

  /// The size a window is asked for: a kiosk covers the display it owns,
  /// anything else gets what it asked for or the default.
  static Size preferredSizeFor(DVWindowRequest? request, List<DVDisplay> displays) {
    if (request?.kind == 'kiosk' && request?.displayId != null) {
      for (final DVDisplay d in displays) {
        if (d.id == request!.displayId) return d.bounds.size;
      }
    }
    return request?.size ?? defaultSize;
  }

  @override
  DVWindowSurface create(DVWindow window, Widget content) {
    final request = _DVWindowBindings.requestFor(window.nativeId);
    return _FlutterWindowSurface(
      window,
      content,
      // RegularWindowController, and the size is `preferred`: the platform
      // may not honour either. Named for the window kind rather than generic,
      // because Flutter has a controller per kind -- dialog, popup, tooltip,
      // satellite -- and the owned kinds are not wired up yet.
      // No preferredConstraints: DVWindowOptions.constraints is not carried
      // in the window.open payload yet, and passing null here would look like
      // it had been considered.
      RegularWindowController(
        preferredSize: preferredSizeFor(request, DV.Platform.Window.displays.value),
        title: request?.title,
      ),
    );
  }
}

class _FlutterWindowSurface implements DVWindowSurface {
  _FlutterWindowSurface(this.window, this._child, this._controller);

  @override
  final DVWindow window;
  final Widget _child;
  final RegularWindowController _controller;

  @override
  Widget get content => RegularWindow(controller: _controller, child: _child);

  @override
  void destroy() => _controller.destroy();
}
