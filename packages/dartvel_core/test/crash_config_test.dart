// dartvel.crashes: what a pubspec says about crash reporting, read strictly.
//
// Every value here has a default, and that is the trap: a setting that is
// misspelt, mistyped or out of range and quietly replaced by its default
// looks exactly like a setting that was honoured. `nonFatalSampleRate: 25`
// meaning a quarter would keep every non-fatal error; `enabled: no` is the
// string "no" to YAML, and read loosely it is truthy; `breadcrumb: 16` is a
// key nobody reads. Each is refused, naming the key, rather than defaulted.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Matcher refusing(String key) => throwsA(
      isA<ArgumentError>().having(
        (ArgumentError e) => '${e.message} ${e.name}',
        'message',
        contains(key),
      ),
    );

void main() {
  test('nothing declared is enabled everywhere with the runtime defaults', () {
    final DVCrashConfig config = DVCrashConfig.parse(null);

    for (final DVCrashBuildMode mode in DVCrashBuildMode.values) {
      expect(config.enabledIn(mode), isTrue);
    }
    expect(config.sink, DVCrashSinkChoice.none);
    expect(config.nonFatalSampleRate, 1);
    expect(config.breadcrumbs, 64);
    expect(config.fullReportsPerRelease, 5);
    expect(config.identityConsent, isNull);
  });

  test('every declared value is read', () {
    final DVCrashConfig config = DVCrashConfig.parse(<String, Object?>{
      'enabled': true,
      'disabledIn': <Object?>['debug', 'profile'],
      'sink': 'none',
      'nonFatalSampleRate': 0.25,
      'breadcrumbs': 16,
      'fullReportsPerRelease': 3,
      'identity': <String, Object?>{'consent': 'crash_identity'},
    });

    expect(config.enabledIn(DVCrashBuildMode.debug), isFalse);
    expect(config.enabledIn(DVCrashBuildMode.profile), isFalse);
    expect(config.enabledIn(DVCrashBuildMode.release), isTrue);
    expect(config.nonFatalSampleRate, 0.25);
    expect(config.breadcrumbs, 16);
    expect(config.fullReportsPerRelease, 3);
    expect(config.identityConsent, const DVConsentCategory('crash_identity'));
  });

  test('an integer sample rate of 0 or 1 is a rate', () {
    expect(
      DVCrashConfig.parse(<String, Object?>{'nonFatalSampleRate': 0})
          .nonFatalSampleRate,
      0,
    );
  });

  test('enabled: false disables every build', () {
    final DVCrashConfig config =
        DVCrashConfig.parse(<String, Object?>{'enabled': false});
    for (final DVCrashBuildMode mode in DVCrashBuildMode.values) {
      expect(config.enabledIn(mode), isFalse);
    }
  });

  test('the parsed configuration round-trips through its declaration', () {
    final Map<String, Object?> declared = <String, Object?>{
      'disabledIn': <Object?>['debug'],
      'nonFatalSampleRate': 0.5,
      'breadcrumbs': 8,
      'fullReportsPerRelease': 2,
      'identity': <String, Object?>{'consent': 'crash_identity'},
    };
    final DVCrashConfig config = DVCrashConfig.parse(declared);

    final DVCrashConfig again = DVCrashConfig.parse(config.toDeclaration());
    expect(again.enabledIn(DVCrashBuildMode.debug), isFalse);
    expect(again.nonFatalSampleRate, 0.5);
    expect(again.breadcrumbs, 8);
    expect(again.fullReportsPerRelease, 2);
    expect(again.identityConsent, const DVConsentCategory('crash_identity'));
  });

  group('the Dartvel sink and what its backend accepts', () {
    test('sink: dartvel, with the ingest limits, round-trips', () {
      final DVCrashConfig config = DVCrashConfig.parse(<String, Object?>{
        'sink': 'dartvel',
        'ingest': <String, Object?>{
          'perInstallPerHour': 10,
          'maxBytes': 65536,
        },
      });
      expect(config.sink, DVCrashSinkChoice.dartvel);
      expect(config.ingestPerInstallPerHour, 10);
      expect(config.ingestMaxBytes, 65536);

      final DVCrashConfig again = DVCrashConfig.parse(config.toDeclaration());
      expect(again.sink, DVCrashSinkChoice.dartvel);
      expect(again.ingestPerInstallPerHour, 10);
      expect(again.ingestMaxBytes, 65536);
    });

    test('the ingest defaults', () {
      final DVCrashConfig config =
          DVCrashConfig.parse(<String, Object?>{'sink': 'dartvel'});
      expect(config.ingestPerInstallPerHour, 30);
      expect(config.ingestMaxBytes, 262144);
    });

    for (final (String key, Object? ingest) in <(String, Object?)>[
      ('ingest', 'strict'),
      ('ingest.perInstallPerHour', <String, Object?>{'perInstallPerHour': 0}),
      ('ingest.maxBytes', <String, Object?>{'maxBytes': 100}),
      ('ingest.maxBytes', <String, Object?>{'maxBytes': '1MB'}),
      ('ingest.perInstall', <String, Object?>{'perInstall': 5}),
    ]) {
      test('refuses $key: $ingest', () {
        expect(
          () => DVCrashConfig.parse(<String, Object?>{
            'sink': 'dartvel',
            'ingest': ingest,
          }),
          refusing(key),
        );
      });
    }
  });

  group('refused, naming the key, never defaulted', () {
    final Map<String, Map<String, Object?>> cases =
        <String, Map<String, Object?>>{
      'enabled': <String, Object?>{'enabled': 'no'},
      'disabledIn': <String, Object?>{'disabledIn': 'release'},
      'disabledIn ': <String, Object?>{
        'disabledIn': <Object?>['staging'],
      },
      'sink': <String, Object?>{'sink': 'sentry'},
      'sink  ': <String, Object?>{'sink': 7},
      'nonFatalSampleRate': <String, Object?>{'nonFatalSampleRate': 25},
      'nonFatalSampleRate ': <String, Object?>{'nonFatalSampleRate': -0.1},
      'nonFatalSampleRate  ': <String, Object?>{'nonFatalSampleRate': '0.5'},
      'breadcrumbs': <String, Object?>{'breadcrumbs': -1},
      'breadcrumbs ': <String, Object?>{'breadcrumbs': 2.5},
      'fullReportsPerRelease': <String, Object?>{'fullReportsPerRelease': 0},
      'identity': <String, Object?>{'identity': 'crash_identity'},
      'identity.consent': <String, Object?>{
        'identity': <String, Object?>{'consent': ''},
      },
      'identity.consenting': <String, Object?>{
        'identity': <String, Object?>{'consenting': 'crash_identity'},
      },
      'breadcrumb': <String, Object?>{'breadcrumb': 16},
    };
    for (final MapEntry<String, Map<String, Object?>> c in cases.entries) {
      test('${c.key.trim()}: ${c.value.values.single}', () {
        expect(() => DVCrashConfig.parse(c.value), refusing(c.key.trim()));
      });
    }

    test('a section that is not a map', () {
      expect(() => DVCrashConfig.parse('on'), refusing('dartvel.crashes'));
    });
  });
}
