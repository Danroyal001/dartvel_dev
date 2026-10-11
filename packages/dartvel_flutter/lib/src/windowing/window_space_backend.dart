/// The extension point behind volumes and immersive spaces on `DV.Window`.
///
/// `DV.Window.open(route, options: DVWindowOptions(kind: .volume))` always
/// presents the route. What can present it in space (a headset runtime, a
/// spatial-computing SDK) is not part of the framework: a package registers a
/// [DVWindowSpaceBackend] with `DVWindowManager.registerSpaceBackend` and the
/// window manager hands it each request. With no backend registered a volume
/// or immersive request is a page and the window says why (`DV-WINDOW-014`,
/// `DV-WINDOW-015`).
library;

import 'window.dart';

/// A request to present a route in space.
class const DVWindowSpaceRequest({
  required final DVWindowKind kind,
  required final String route,
  final Object? options = null,
});

/// A space that is presenting a window's route. Closing the window closes it;
/// the system ending it closes the window.
abstract interface class DVWindowSpaceSession {
  /// Emits once when the space ends without the window asking (the home
  /// gesture, another application taking the immersive space).
  Stream<void> get ended;

  /// Ends the space. Safe to call twice.
  Future<void> close();
}

/// What a backend answers: a session, or the reason there is none.
class DVWindowSpacePresentation {
  const DVWindowSpacePresentation._(this.session, this.degradation, this.codes);

  /// The route is presented in space by [session].
  const DVWindowSpacePresentation.presented(DVWindowSpaceSession session)
      : this._(session, DVWindowDegradation.none, const <String>[]);

  /// The route is presented as a page. [codes] are the diagnostic codes that
  /// say why, cause first, the `DV-WINDOW-014`/`015` code last.
  const DVWindowSpacePresentation.refused(
    DVWindowDegradation degradation, {
    List<String> codes = const <String>[],
  }) : this._(null, degradation, codes);

  final DVWindowSpaceSession? session;
  final DVWindowDegradation degradation;
  final List<String> codes;
}

/// Presents windows in space.
abstract interface class DVWindowSpaceBackend {
  /// What this target can do in space, reported as
  /// `DV.Window.capability.spatial`. Null on a target that is not a headset or
  /// glasses.
  Object? get capability;

  /// Whether tabs are presented as panels, so tearing one out is possible.
  bool get panels;

  /// Presents [request] in space, or answers why it cannot. Never throws for a
  /// device failure: the window falls back to a page with the codes returned.
  Future<DVWindowSpacePresentation> present(DVWindowSpaceRequest request);

  /// Forgets what a test or a restart left behind. Called by
  /// `DVWindowManager.reset`.
  void reset();
}
