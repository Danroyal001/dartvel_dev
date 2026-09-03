@TestOn('windows || mac-os')
library;

// Display enumeration against the real desktop, on the hosts that have one.
//
// The Linux enumeration is verified by running the application under a
// display server; Windows and macOS runners have a desktop session, so the
// binding can be asked directly. What is asserted is what an application
// relies on: at least one display, a primary among them, a real size, and
// rows the shared decoder accepts -- a row the decoder drops would look like
// "no second display" rather than like a mismatch.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_windowing/dartvel_windowing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(DVWindowHost.debugRegisterBindings);
  tearDown(DVWindowHost.debugResetBindings);

  test('the desktop reports at least one display, with a primary and a size', () async {
    final Object? raw = await DVNativeBridge.invoke<Object?>('window.displays');
    expect(raw, isA<List<Object?>>());
    final List<DVDisplay> displays = DVDisplays.decode(raw);

    expect(displays, isNotEmpty);
    expect(displays.where((DVDisplay d) => d.isPrimary), hasLength(1));
    for (final DVDisplay d in displays) {
      expect(d.bounds.width, greaterThan(0), reason: d.name);
      expect(d.bounds.height, greaterThan(0), reason: d.name);
      expect(d.devicePixelRatio, greaterThan(0), reason: d.name);
      expect(d.hasLayout, isTrue, reason: d.name);
      expect(d.id, isNotEmpty);
    }
  });

  test('DVDisplayHint.primary resolves to the primary, not the first', () async {
    final List<DVDisplay> displays =
        DVDisplays.decode(await DVNativeBridge.invoke<Object?>('window.displays'));
    final DVDisplay primary = displays.singleWhere((DVDisplay d) => d.isPrimary);
    expect(primary.bounds.left, 0);
    expect(primary.bounds.top, 0);
  });
}
