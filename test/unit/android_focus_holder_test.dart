// Who holds input focus on the emulator.
//
// From Android 10 an application reads the clipboard only while it holds
// input focus, and ClipboardManager answers null rather than refusing when it
// does not. On the runners a "Pixel Launcher isn't responding" dialog took
// focus in every run where the clipboard round trip read null, and in none
// of the runs where it read the value -- so the device checks say who held
// focus when the bindings test ran. A parser that always named the
// application would hide exactly that.
import 'package:test/test.dart';

import '../../tool/ci/android_device_checks.dart';

// Trimmed from `adb shell dumpsys window`, API 34.
const String _app = '''
  mCurrentFocus=Window{3c1d2e9 u0 com.example.dartvel_example/com.example.dartvel_example.MainActivity}
  mFocusedApp=ActivityRecord{1b2c3d4 u0 com.example.dartvel_example/.MainActivity t12}
''';
const String _anr = '''
  mCurrentFocus=Window{8a7b6c5 u0 Application Not Responding: com.google.android.apps.nexuslauncher}
  mFocusedApp=ActivityRecord{1b2c3d4 u0 com.example.dartvel_example/.MainActivity t12}
''';
const String _nothing = '''
  mCurrentFocus=null
  mFocusedApp=null
''';

void main() {
  test('the application holding focus is named', () {
    expect(
      dvFocusHolder(_app),
      'com.example.dartvel_example/com.example.dartvel_example.MainActivity',
    );
    expect(dvApplicationHasFocus(_app, 'com.example.dartvel_example'), isTrue);
  });

  test(
    'a not-responding dialog over the application is not the application',
    () {
      // The focused *app* is still ours in this dump -- only the window says
      // otherwise, which is why the window is the line that is read.
      expect(
        dvFocusHolder(_anr),
        'Application Not Responding: com.google.android.apps.nexuslauncher',
      );
      expect(
        dvApplicationHasFocus(_anr, 'com.example.dartvel_example'),
        isFalse,
      );
    },
  );

  test('no focused window is nobody, not the application', () {
    expect(dvFocusHolder(_nothing), isNull);
    expect(
      dvApplicationHasFocus(_nothing, 'com.example.dartvel_example'),
      isFalse,
    );
  });

  test('a dump with no focus line at all is unknown', () {
    expect(
      dvFocusHolder('WINDOW MANAGER WINDOWS (dumpsys window windows)'),
      isNull,
    );
  });
}
