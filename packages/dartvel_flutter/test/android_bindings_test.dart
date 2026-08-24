// Android platform bindings — none yet, and this records why so the absence
// stays deliberate rather than becoming something nobody remembers.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android claims nothing, and register reports false', () {
    // The route is fixed by the native integration rule: JNI, never a platform
    // channel. Everything worth binding is reached through
    // Context.getSystemService, and package:jni 1.0.0 does not expose an
    // application Context — GetApplicationContext lives in its internal
    // generated bindings.
    //
    // A binding built on another package's internals compiles today and breaks
    // on a patch release, in somebody's shipped application rather than here.
    expect(DVAndroidBindings.implemented, isEmpty);
    expect(DVAndroidBindings.register(), isFalse);
    expect(DVAndroidBindings.isRegistered, isFalse);
  });

  test('the other platforms are not empty, so this is a blocker not a pattern',
      () {
    // Guards against the empty set being read as "that is just how these
    // start". Four platforms have bindings; Android is stuck on a specific
    // missing piece.
    expect(DVWebBindings.implemented, isNotEmpty);
    expect(DVWindowsBindings.implemented, isNotEmpty);
    expect(DVMacosBindings.implemented, isNotEmpty);
    expect(DVIosBindings.implemented, isNotEmpty);
  });
}
