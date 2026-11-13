// Android runs Dart on the app's main thread (Flutter merged the UI and
// platform threads), so a long JNI call made from Dart freezes the app and,
// past five seconds, Android shows "app isn't responding". A launcher that
// lists every installed app on each return to the home screen did exactly
// that on a slow phone. Such calls run on a background isolate.
import 'dart:isolate';

import 'package:dartvel_flutter/src/platform/android/android_background.dart';
import 'package:flutter_test/flutter_test.dart';

String _isolateName() => Isolate.current.debugName ?? '';

int _fails() => throw StateError('no JNI on this isolate');

void main() {
  test('the work runs on another isolate, not the one that asked', () async {
    final String here = _isolateName();
    final String there = await dvAndroidOffMainThread(_isolateName);
    expect(there, isNot(here));
  });

  test('a result crosses back intact', () async {
    final List<Map<String, Object?>> apps = await dvAndroidOffMainThread(() => <Map<String, Object?>>[
          <String, Object?>{'package': 'com.termux', 'label': 'Termux'},
        ]);
    expect(apps.single['label'], 'Termux');
  });

  test('work that cannot run off the main thread still runs, here', () async {
    int calls = 0;
    int local() {
      calls++;
      if (Isolate.current.debugName != _mainName) throw StateError('background');
      return 7;
    }

    _mainName = Isolate.current.debugName;
    expect(await dvAndroidOffMainThread(local), 7);
    expect(calls, 1, reason: 'the background attempt failed before counting in this isolate; the local run counted once');
  });

  test('an error on both is the caller\'s to see', () async {
    await expectLater(dvAndroidOffMainThread(_fails), throwsStateError);
  });
}

String? _mainName;
