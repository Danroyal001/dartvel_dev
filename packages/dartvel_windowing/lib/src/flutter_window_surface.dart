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
  /// `DVWindowOptions.size` is optional and Flutter's `WindowController`
  /// requires one, so the gap has to be filled somewhere. It is filled here,
  /// visibly, rather than by making the Dartvel option required: a projector
  /// window's real size comes from the display it is going to, which is a
  /// separate question from what a window defaults to.
  static const Size defaultSize = Size(1280, 720);

  @override
  DVWindowSurface create(DVWindow window, Widget content) {
    final request = _DVWindowBindings.requestFor(window.nativeId);
    return _FlutterWindowSurface(
      window,
      content,
      WindowController(
        size: request?.size ?? defaultSize,
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
  final WindowController _controller;

  @override
  Widget get content => Window(controller: _controller, child: _child);

  @override
  @override
  void setFullscreen(bool fullscreen, {DVEngineDisplay? on}) {
    final Display? display = on == null
        ? null
        : PlatformDispatcher.instance.displays
            .where((Display d) => d.id == on.id)
            .firstOrNull;
    _controller.setFullscreen(fullscreen, display: display);
  }

  @override
  void destroy() => _controller.destroy();
}
