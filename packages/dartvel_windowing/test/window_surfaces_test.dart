// The reconciler between DVWindowManager's window list and the OS surfaces
// that render them.
//
// Two rules carry the weight. A surface is never created before the first
// frame, because building a window controller while the engine is still coming
// up ends the process with a GLX BadAccess rather than an exception -- on
// Flutter master that happens even for a single window. And a window that
// degraded to a page must never get a surface, or the route would be presented
// twice.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_windowing/dartvel_windowing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const operatorRoute = DVRouteTarget('/operator');
const projectorRoute = DVRouteTarget('/projector');

/// Records what the reconciler asked for, without touching a real window.
class _RecordingFactory implements DVWindowSurfaceFactory {
  final List<String> created = <String>[];
  final List<String> destroyed = <String>[];

  @override
  DVWindowSurface create(DVWindow window, Widget content) {
    created.add(window.route.path);
    return _RecordingSurface(window, content, this);
  }
}

class _RecordingSurface implements DVWindowSurface {
  _RecordingSurface(this.window, this.content, this._factory);
  @override
  final DVWindow window;
  @override
  final Widget content;
  final _RecordingFactory _factory;

  @override
  void destroy() => _factory.destroyed.add(window.route.path);
}

DVWindow _window(DVRouteTarget route, {DVWindowPresentation presentation = DVWindowPresentation.window}) =>
    DVWindow(
      route: route,
      kind: DVWindowKind.regular,
      presentation: presentation,
      degradation: presentation == DVWindowPresentation.window
          ? DVWindowDegradation.none
          : DVWindowDegradation.capabilityUnsupported,
    );

void main() {
  late _RecordingFactory factory;
  late DVWindowSurfaces surfaces;

  setUp(() {
    factory = _RecordingFactory();
    surfaces = DVWindowSurfaces(
      factory: factory,
      contentFor: (DVWindow w) => Text(w.route.path, textDirection: TextDirection.ltr),
    );
  });

  test('creates nothing before the first frame', () {
    surfaces.sync(<DVWindow>[_window(projectorRoute)]);

    expect(factory.created, isEmpty,
        reason: 'a controller built before the engine is up kills the process');
    expect(surfaces.live, isEmpty);
  });

  test('creates what was pending once the first frame has rendered', () {
    surfaces.sync(<DVWindow>[_window(projectorRoute)]);
    surfaces.markFirstFrame();

    expect(factory.created, <String>['/projector']);
    expect(surfaces.live.map((s) => s.window.route.path), <String>['/projector']);
  });

  test('creates in open order, and only once per window', () {
    surfaces.markFirstFrame();
    final operator = _window(operatorRoute);
    final projector = _window(projectorRoute);

    surfaces.sync(<DVWindow>[operator]);
    surfaces.sync(<DVWindow>[operator, projector]);
    surfaces.sync(<DVWindow>[operator, projector]);

    expect(factory.created, <String>['/operator', '/projector']);
  });

  test('destroys the surface of a window that has gone', () {
    surfaces.markFirstFrame();
    final operator = _window(operatorRoute);
    final projector = _window(projectorRoute);
    surfaces.sync(<DVWindow>[operator, projector]);

    surfaces.sync(<DVWindow>[operator]);

    expect(factory.destroyed, <String>['/projector']);
    expect(surfaces.live.map((s) => s.window.route.path), <String>['/operator']);
  });

  test('gives a degraded window no surface, because it is already a page', () {
    surfaces.markFirstFrame();

    surfaces.sync(<DVWindow>[
      _window(projectorRoute, presentation: DVWindowPresentation.page),
    ]);

    expect(factory.created, isEmpty,
        reason: 'the route is already presented in the main view');
    expect(surfaces.live, isEmpty);
  });
}
