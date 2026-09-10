// The permission-gated Android bindings, on a device.
//
// This is the test the whole Android layer needed and did not have. Every
// binding here reaches Java by name: `JClass.forName` for the class,
// `staticMethodId` for the method and its JNI signature. None of that is
// checked by either compiler, and all of it fails the same way — a lookup
// that throws where nobody is looking, or a binding that answers nothing.
// That is precisely how `GetApplicationContext()` shipped: declared in a
// header, never defined, and every Android binding dead in every real
// application while the capability list claimed them.
//
// So what is asserted is not that a photograph came out well. It is that
// the classes are in the APK, that the methods answer, and that what comes
// back decodes. A permission the manifest declares and the person has not
// granted has an answer -- false -- and getting that answer proves the whole
// path: the generated manifest, the generated Java, the JNI lookup, the JSON
// and the Dart that reads it.
//
// Nothing here opens a dialog. `permissions.isGranted` never shows one, and
// the camera, the picker, contacts and location each wait for somebody who
// is not there. Those are asserted as registered and left alone.
//
// Run with: flutter test integration_test/android_capture_test.dart -d emulator-5554
@TestOn('!browser')
library;

import 'dart:io' as io;

import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerPlatformBindings();
  });

  testWidgets('the Android bindings registered at all', (WidgetTester t) async {
    if (!io.Platform.isAndroid) {
      markTestSkipped('the Android bindings are Android\'s');
      return;
    }

    // The check that was missing. Registration returning false is how an
    // APK without the generated classes looks, and every binding then
    // answers null -- which is also how an unsupported platform looks.
    expect(DVAndroidBindings.isRegistered, isTrue,
        reason: 'the Android bindings did not register. '
            '${DVAndroidBindings.lastFailure ?? 'No reason was recorded.'}');
  });

  testWidgets('every capture binding is bound, not merely claimed',
      (WidgetTester t) async {
    if (!io.Platform.isAndroid) {
      markTestSkipped('the Android bindings are Android\'s');
      return;
    }

    for (final String name in DVAndroidCapture.implemented) {
      expect(DVNativeBridge.isRegistered(name), isTrue,
          reason: 'the capability list claims $name and nothing is registered '
              'under it. ${DVAndroidCapture.lastFailure ?? ''}');
    }
    // And the bridge class was found, which is the difference between a
    // binding that works and one that throws the moment it is called.
    expect(DVAndroidCapture.lastFailure, isNull,
        reason: 'the capture bridge class is not in this APK. Only '
            '`dartvel build android` writes it.');
  });

  testWidgets('a permission that needs nothing is held', (WidgetTester t) async {
    if (!io.Platform.isAndroid) {
      markTestSkipped('the Android bindings are Android\'s');
      return;
    }

    // The end-to-end proof, with no dialog in it: Dart called into the
    // generated Java by name, the method answered, and the JSON decoded.
    // The clipboard needs no Android permission, so the answer is true on
    // any device -- and getting *an answer at all* is what is being checked.
    expect(await DV.Platform.permissions.isGranted('clipboard'), isTrue);
  });

  testWidgets('a declared permission nobody granted answers false',
      (WidgetTester t) async {
    if (!io.Platform.isAndroid) {
      markTestSkipped('the Android bindings are Android\'s');
      return;
    }

    // camera is in the example's dartvel.android.permissions, so the build
    // put it in the manifest. Nothing has granted it on a fresh emulator.
    //
    // False rather than a throw is the whole point: an undeclared permission
    // throws and names pubspec.yaml, because Android refuses that one
    // instantly with no dialog and no way for a person to say yes. If this
    // throws, the manifest generation did not reach the installed APK.
    expect(await DV.Platform.permissions.isGranted('camera'), isFalse);
  });

  testWidgets('a permission Dartvel has no name for is not a quiet no',
      (WidgetTester t) async {
    if (!io.Platform.isAndroid) {
      markTestSkipped('the Android bindings are Android\'s');
      return;
    }

    // A typo answered `false` is a screen that asks for a permission no
    // button can grant.
    await expectLater(
      DV.Platform.permissions.isGranted('camrea'),
      throwsA(isA<StateError>()),
    );
  });
}
