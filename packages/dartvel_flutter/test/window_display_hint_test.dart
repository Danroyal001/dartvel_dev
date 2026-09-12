// Two different things had one name.
//
// `DV-WINDOW-013` is "the `display:` hint matched no connected display; the OS
// placed the window" -- a hint that went unhonoured, on an ordinary window
// that opened anyway. `DV-WINDOW-010` is "the kiosk window's display is
// unavailable; presented in place, fullscreen" -- a different situation, a
// different level of alarm, and a different fix.
//
// Both reported `DVWindowDegradation.displayUnavailable`, whose `code` said
// 013. So a kiosk window presenting in place logged 010 and carried a
// degradation naming 013: `win.degradation.code` and `win.codes` disagreed
// about the same window, and `dartvel explain` on either one described the
// other situation.
//
// The hint miss is its own member now. `displayUnavailable` keeps the kiosk
// meaning and names the code that path has always logged.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> display(String id, String name,
        {bool primary = false, double left = 0}) =>
    <String, Object?>{
      'id': id,
      'name': name,
      'devicePixelRatio': 1.0,
      'width': 1920.0,
      'height': 1080.0,
      'refreshRate': 60.0,
      'isPrimary': primary,
      'left': left,
      'top': 0.0,
    };

DVKioskPolicy customerDisplay() => DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': 'display',
        'home': '/customer-display',
        'routes': <String, Object?>{
          'allow': <String>['/customer-display/**'],
        },
        'session': <String, Object?>{'idleTimeout': '60s', 'onIdle': 'reset'},
        'exit': <String, Object?>{'method': 'adminAuth'},
      },
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, Object?>> displays;

  setUp(() {
    DVWindowManager.reset();
    DVWindowManager.capabilityOverride = const DVWindowingCapability(
      multiWindow: true,
      sameEngine: true,
      tearOut: true,
      displayKiosk: true,
    );
    displays = <Map<String, Object?>>[
      display('1', 'Operator', primary: true),
      display('2', 'Customer', left: 1920),
    ];
    DVNativeBridge.register('window.displays', (Object? _) => displays);
    var n = 0;
    DVNativeBridge.register('window.open', (Object? _) => 'win-${++n}');
    DVNativeBridge.register('window.close', (Object? _) => true);
  });

  tearDown(() {
    DVWindowManager.reset();
    for (final String name in <String>[
      'window.displays',
      'window.open',
      'window.close',
    ]) {
      DVNativeBridge.unregister(name);
    }
  });

  group('a hint that matches no connected display', () {
    test('is reported as displayHintUnmatched, not as a missing display',
        () async {
      final DVWindow window = await DV.Platform.Window.open(
        const DVRouteTarget('/orders'),
        options: DVWindowOptions(display: DVDisplayHint.byName('Projector')),
      );

      expect(window.degradation, DVWindowDegradation.displayHintUnmatched);
      expect(window.degradation.code, 'DV-WINDOW-013');
      expect(window.presentation, DVWindowPresentation.window,
          reason: 'the window opened; only the hint went unhonoured');
    });

    test('a hint that does match degrades nothing', () async {
      // The control. If this ever reports a degradation, the one above is
      // passing for the wrong reason.
      final DVWindow window = await DV.Platform.Window.open(
        const DVRouteTarget('/orders'),
        options: DVWindowOptions(display: DVDisplayHint.byName('Customer')),
      );

      expect(window.degradation, DVWindowDegradation.none);
    });

    test('the resolver says the same thing on its own', () {
      final List<DVDisplay> connected = DVDisplays.decode(<Object?>[
        display('1', 'Operator', primary: true),
      ]);

      final DVDisplayResolution result =
          DVDisplays.resolve(connected, DVDisplayHint.byName('Projector'));

      expect(result.display, isNull, reason: 'never another display');
      expect(result.degradation, DVWindowDegradation.displayHintUnmatched);
    });
  });

  group('a kiosk window whose display is gone', () {
    test('carries the code it logs', () async {
      // 010, in both places. The window and its log agreed about what
      // happened only if you did not look at `degradation.code`.
      displays = <Map<String, Object?>>[
        display('1', 'Operator', primary: true),
      ];

      final DVWindow customer = await DV.Platform.Window.open(
        const DVRouteTarget('/customer-display'),
        options: DVWindowOptions(
          kind: DVWindowKind.kiosk,
          display: DVDisplayHint.byName('Customer'),
          kiosk: DVWindowKiosk(policy: customerDisplay()),
        ),
      );

      expect(customer.degradation, DVWindowDegradation.displayUnavailable);
      expect(customer.codes, contains('DV-WINDOW-010'));
      expect(customer.degradation.code, 'DV-WINDOW-010',
          reason: 'the member must name the diagnostic this path reports');
      expect(customer.presentation, DVWindowPresentation.page,
          reason: 'in place, fullscreen');
    });
  });
}
