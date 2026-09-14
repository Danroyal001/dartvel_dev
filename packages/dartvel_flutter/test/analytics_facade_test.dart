// DV.Analytics and DV.Privacy: the names an application reaches the
// pipeline and the privacy walk by.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _Viewed extends DVAnalyticsEvent {
  const _Viewed();
  @override
  String get name => 'viewed';
  @override
  DVConsentCategory get category => const DVConsentCategory('product');
}

void main() {
  setUp(() {
    DVAnalyticsRuntime.resetForTest();
    DVPrivacyRuntime.resetForTest();
  });

  test('DV.Analytics throws until analytics is declared', () {
    expect(() => DV.Analytics, throwsStateError);
  });

  test('DV.Analytics is the started runtime, and tracks through consent',
      () async {
    final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
      settings: DVAnalyticsSettings.fromConfig(<String, Object?>{
        'consent': <String, Object?>{
          'version': '1',
          'categories': <String, Object?>{
            'product': <String, Object?>{'default': 'denied'},
          },
        },
      }),
      database: MemoryDVDatabaseAdapter.new,
    );
    expect(identical(DV.Analytics, runtime), isTrue);
    final DVTrackResult result = await DV.Analytics.track(const _Viewed());
    expect(result.accepted, isFalse);
    expect(result.code, 'DV-ANALYTICS-001');
  });

  test('DV.Privacy throws until configured, then is the configured walk',
      () {
    expect(() => DV.Privacy, throwsStateError);
    DVPrivacyRuntime.configure(
      models: const <DVPrivacyModel>[],
      database: MemoryDVDatabaseAdapter(),
      signingKey: List<int>.filled(32, 7),
    );
    expect(DV.Privacy, isA<DVPrivacy>());
  });
}
