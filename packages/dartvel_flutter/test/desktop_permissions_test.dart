// What a desktop grants without asking, the same on every desktop.
//
// Anything a process may do on its own -- notify, read and write files,
// use the camera and microphone the OS already lets it use, the clipboard
// -- is granted; what needs a system service Dartvel has no binding for is
// answered false rather than with a prompt that never comes. This answer
// was Linux's alone; Windows and macOS threw "binding not registered" for
// the same question.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('what a process may do on its own is granted', () {
    for (final String p in <String>['notifications', 'storage', 'photos', 'files', 'camera', 'microphone', 'clipboard']) {
      expect(DVDesktopPermissions.granted(p), isTrue, reason: p);
      expect(DVDesktopPermissions.granted(p.toUpperCase()), isTrue, reason: 'case does not matter');
    }
  });

  test('what needs a system service is refused, not prompted', () {
    for (final String p in <String>['location', 'bluetooth', 'contacts', 'nfc', 'biometrics', '']) {
      expect(DVDesktopPermissions.granted(p), isFalse, reason: p);
    }
  });

  test('the binding answer reads the permission from the arguments', () {
    expect(DVDesktopPermissions.answer(<String, Object?>{'permission': 'camera'}), isTrue);
    expect(DVDesktopPermissions.answer(<String, Object?>{'permission': 'location'}), isFalse);
    expect(DVDesktopPermissions.answer(null), isFalse);
  });
}
