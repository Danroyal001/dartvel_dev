// Code that starts before DV.Analytics can still reach it.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVAnalyticsSettings settings() =>
    DVAnalyticsSettings.fromConfig(<String, Object?>{
      'consent': <String, Object?>{
        'version': '2026-11-18',
        'categories': <String, Object?>{
          'analytics': <String, Object?>{'default': 'denied'},
        },
      },
    });

void main() {
  setUp(DVAnalyticsRuntime.resetForTest);
  tearDown(DVAnalyticsRuntime.resetForTest);

  test('a listener added before start is called when it starts, once', () {
    final List<DVAnalyticsRuntime> heard = <DVAnalyticsRuntime>[];
    DVAnalyticsRuntime.whenStarted(heard.add);
    expect(heard, isEmpty);
    final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
        settings: settings(), database: MemoryDVDatabaseAdapter.new);
    expect(heard, <DVAnalyticsRuntime>[runtime]);
  });

  test('a listener added after start is called at once', () {
    final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
        settings: settings(), database: MemoryDVDatabaseAdapter.new);
    final List<DVAnalyticsRuntime> heard = <DVAnalyticsRuntime>[];
    DVAnalyticsRuntime.whenStarted(heard.add);
    expect(heard, <DVAnalyticsRuntime>[runtime]);
  });

  test('a listener that throws does not stop analytics starting', () async {
    DVAnalyticsRuntime.whenStarted((_) => throw StateError('broken'));
    final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
        settings: settings(), database: MemoryDVDatabaseAdapter.new);
    await runtime.ready;
    expect(DVAnalyticsRuntime.current, runtime);
  });
}
