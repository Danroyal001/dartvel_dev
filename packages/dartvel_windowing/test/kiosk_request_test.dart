// A kiosk-kind window request: the kind and the display it owns travel
// with the request, and the surface sizes it to that display, so the
// window opened for a kiosk covers the display it was given rather than
// the default 1280 by 720.
import 'dart:ui' show Rect, Size;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_windowing/dartvel_windowing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(DVWindowHost.debugRegisterBindings);
  tearDown(DVWindowHost.debugResetBindings);

  test('the request keeps the kind and the display', () async {
    final String? id = await DVNativeBridge.invoke<String>('window.open', <String, Object?>{
      'route': '/customer-display',
      'kind': 'kiosk',
      'displayId': '2',
    });
    final DVWindowRequest? request = DVWindowHost.debugRequestFor(id);
    expect(request, isNotNull);
    expect(request!.kind, 'kiosk');
    expect(request.displayId, '2');
  });

  test('a kiosk request is sized to its display; an ordinary one to what it asked', () {
    final List<DVDisplay> displays = <DVDisplay>[
      const DVDisplay(id: '1', name: 'Staff', bounds: Rect.fromLTWH(0, 0, 1920, 1080), devicePixelRatio: 1, refreshRate: 60, isPrimary: true, hasLayout: true),
      const DVDisplay(id: '2', name: 'Customer', bounds: Rect.fromLTWH(1920, 0, 1080, 1920), devicePixelRatio: 1, refreshRate: 60, isPrimary: false, hasLayout: true),
    ];
    expect(
      DVFlutterWindowSurfaceFactory.preferredSizeFor(const DVWindowRequest(kind: 'kiosk', displayId: '2'), displays),
      const Size(1080, 1920),
    );
    expect(
      DVFlutterWindowSurfaceFactory.preferredSizeFor(const DVWindowRequest(size: Size(800, 600)), displays),
      const Size(800, 600),
    );
    expect(
      DVFlutterWindowSurfaceFactory.preferredSizeFor(const DVWindowRequest(kind: 'kiosk', displayId: '9'), displays),
      DVFlutterWindowSurfaceFactory.defaultSize,
      reason: 'a display that is not there: the default, and the window manager already said DV-WINDOW-010',
    );
  });
}
