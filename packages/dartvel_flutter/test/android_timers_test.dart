// What the Android timer receiver records while the app is away, read back
// as the actions the app applies.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/android/android_timers_jni.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each line the receiver wrote is the action it names', () {
    final List<DVTimerAction> actions = dvAndroidTimerEvents(<String>[
      'eggs\tsnooze-5\t1795700000000',
      'rice\tdismiss\t1795700000001',
    ]);
    expect(actions.map((DVTimerAction a) => '${a.id} ${a.kind.name} ${a.by.inMinutes}'),
        <String>['eggs snooze 5', 'rice dismiss 0']);
  });

  test('a damaged line is skipped, not applied as something else', () {
    expect(dvAndroidTimerEvents(<String>['', 'eggs', 'eggs\tsnooze-0\t1', 'eggs\treboot\t1', '\tdismiss\t1']), isEmpty);
  });

  test('the events file is where the receiver writes it', () {
    expect(dvAndroidTimerEventsFile, 'dartvel-timers/events.txt');
  });
}
