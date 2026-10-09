// The iOS device bindings, on a simulator.
//
// The Linux suite proves what each binding asks the Swift shim and what it
// makes of the answer. It cannot prove the shim is in the app, that its
// symbols resolve, that the Swift compiles, or that iOS answers at all. This
// does, for every binding that answers without somebody at the screen.
//
// What is left alone: the camera (a simulator has none), the pickers, the
// share sheet's choice, Face ID and Guided Access each wait for a person or a
// supervised device. They are asserted registered, which proves the shim and
// the handler table, and not called.
//
// Built with `dartvel build ios --simulator --debug` first, which writes the
// shim into ios/Runner and the target; then:
//   flutter test integration_test/ios_device_apis_test.dart -d <simulator id>
@TestOn('!browser')
library;

import 'dart:io' as io;

import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerPlatformBindings);

  bool skipOffIos() {
    if (io.Platform.isIOS) return false;
    markTestSkipped("the iOS bindings are iOS's");
    return true;
  }

  testWidgets('the shim is in the app and every claimed name is registered', (WidgetTester t) async {
    if (skipOffIos()) return;
    expect(DVIosBindings.isRegistered, isTrue);
    expect(DVIosBindings.lastFailure, isNull,
        reason: 'the shim did not load: ${DVIosBindings.lastFailure}');
    for (final String name in DVIosBindings.implemented) {
      expect(DVNativeBridge.isRegistered(name), isTrue, reason: '$name is claimed and not registered');
    }
  });

  testWidgets('haptics answer true, which DV.Platform reads as a bool', (WidgetTester t) async {
    if (skipOffIos()) return;
    // This threw "returned Null, expected bool" on every iOS device before.
    await DV.Platform.haptics.impact();
    await DV.Platform.haptics.lightVibrate();
  });

  testWidgets('screen.geometry is the simulated screen, in pixels', (WidgetTester t) async {
    if (skipOffIos()) return;
    final Map<Object?, Object?> geometry =
        await DVNativeBridge.require<Map<Object?, Object?>>('screen.geometry');
    expect(geometry['width'], greaterThan(300));
    expect(geometry['height'], greaterThan(geometry['width']! as int));
    expect(geometry['devicePixelRatio'], greaterThanOrEqualTo(2));
  });

  testWidgets('the clipboard round-trips', (WidgetTester t) async {
    if (skipOffIos()) return;
    await DV.Platform.clipboard.copy('dartvel ios');
    expect(await DV.Platform.clipboard.paste(), 'dartvel ios');
  });

  testWidgets('permissions answer, and the declared keys reached Info.plist', (WidgetTester t) async {
    if (skipOffIos()) return;
    // Declared in pubspec under dartvel.ios.permissions, so this answers
    // rather than throwing the "not declared" StateError.
    expect(await DV.Platform.permissions.isGranted('camera'), isA<bool>());
    expect(await DV.Platform.permissions.isGranted('clipboard'), isTrue);
    // Not declared: the shim refuses before iOS can terminate the app.
    expect(() => DV.Platform.permissions.isGranted('bluetooth'), throwsStateError);
  });

  testWidgets('location answers the position the job set', (WidgetTester t) async {
    if (skipOffIos()) return;
    // The job grants location with simctl privacy and sets 6.5244,3.3792.
    final Map<String, double> at = await DV.Platform.location.getCoordinates();
    expect(at['latitude'], closeTo(6.5244, 0.01));
    expect(at['longitude'], closeTo(3.3792, 0.01));
  });

  testWidgets('contacts answer the simulator address book', (WidgetTester t) async {
    if (skipOffIos()) return;
    // Granted by the job. The simulator ships sample contacts.
    final List<Map<String, String>> people = await DV.Platform.contacts.getContacts();
    expect(people, isNotEmpty);
    expect(people.first.keys, containsAll(<String>['id', 'name', 'phone']));
  });

  testWidgets('NFC and biometrics answer false on a simulator, not null', (WidgetTester t) async {
    if (skipOffIos()) return;
    expect(await DV.Platform.nfc.isAvailable(), isFalse);
    expect(await DV.Platform.biometrics.canAuthenticate(), isA<bool>());
  });

  testWidgets('the network signal leaves unknown', (WidgetTester t) async {
    if (skipOffIos()) return;
    // NWPathMonitor reports its first path at once.
    for (var i = 0; i < 50 && DV.Platform.network.status == DVNetworkStatus.unknown; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(DV.Platform.network.status, isNot(DVNetworkStatus.unknown));
  });

  testWidgets('files and the device runtime write under Application Support', (WidgetTester t) async {
    if (skipOffIos()) return;
    await DV.Platform.files.writeBytes('probe.bin', <int>[1, 2, 3]);
    expect(await DV.Platform.files.readBytes('probe.bin'), <int>[1, 2, 3]);
    await DV.Platform.files.delete('probe.bin');
    final DVDeviceHealth health = await DV.Platform.device.health();
    expect(health, isNotNull);
  });
}
