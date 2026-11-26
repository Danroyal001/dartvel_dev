// Voice mode in the framework's accessibility controls: an app opts in under
// dartvel.accessibility.defaultControls.voice and names its languages; the
// panel then offers where voice mode sits and the voice language. And an app
// that kept display or voice settings itself before opting in names that key
// once (formerKey), so its visitors keep what they chose.
import 'package:dartvel_core/config.dart';
import 'package:test/test.dart';

void main() {
  group('voice', () {
    test('absent: no voice settings in the panel', () {
      expect(DVAccessibilityDefaultControlsConfig.parse(true).voice, isNull);
    });

    test('true: voice mode in English', () {
      final DVAccessibilityVoiceConfig? voice =
          DVAccessibilityDefaultControlsConfig.parse(<String, Object?>{'voice': true}).voice;
      expect(voice, const DVAccessibilityVoiceConfig());
      expect(voice!.languages, <DVVoiceLanguage>[DVVoiceLanguage.english]);
    });

    test('a list of languages, in the order the panel shows them, and which ones are machine translated', () {
      final DVAccessibilityVoiceConfig voice = DVAccessibilityDefaultControlsConfig.parse(<String, Object?>{
        'voice': <String, Object?>{
          'languages': <Object?>['en', 'pcm', 'yo'],
          'machineTranslated': <Object?>['yo'],
        },
      }).voice!;
      expect(voice.languages.map((DVVoiceLanguage language) => language.code), <String>['en', 'pcm', 'yo']);
      expect(voice.isMachineTranslated(DVVoiceLanguage.yoruba), isTrue);
      expect(voice.isMachineTranslated(DVVoiceLanguage.english), isFalse);
    });

    test('a language the framework does not know is refused, naming it and the known ones', () {
      expect(
        () => DVAccessibilityDefaultControlsConfig.parse(<String, Object?>{
          'voice': <String, Object?>{'languages': <Object?>['en', 'klingon']},
        }),
        throwsA(isA<ArgumentError>()
            .having((ArgumentError e) => '${e.message}', 'message', allOf(contains('klingon'), contains('yo')))),
      );
    });

    test('machine translated must be one of the languages', () {
      expect(
        () => DVAccessibilityDefaultControlsConfig.parse(<String, Object?>{
          'voice': <String, Object?>{'languages': <Object?>['en'], 'machineTranslated': <Object?>['yo']},
        }),
        throwsA(isA<ArgumentError>().having((ArgumentError e) => '${e.message}', 'message', contains('yo'))),
      );
    });

    test('a misspelt voice setting is refused, naming it', () {
      expect(
        () => DVAccessibilityDefaultControlsConfig.parse(<String, Object?>{
          'voice': <String, Object?>{'langauges': <Object?>['en']},
        }),
        throwsA(isA<ArgumentError>().having((ArgumentError e) => '${e.message}', 'message', contains('langauges'))),
      );
    });

    test('the generated runtime gets the same value back as Dart source', () {
      const DVAccessibilityDefaultControlsConfig config = DVAccessibilityDefaultControlsConfig(
        enabled: true,
        floatingButton: false,
        voice: DVAccessibilityVoiceConfig(
          languages: <DVVoiceLanguage>[DVVoiceLanguage.english, DVVoiceLanguage.hausa],
          machineTranslated: <DVVoiceLanguage>{DVVoiceLanguage.hausa},
        ),
        formerKey: 'shop.display',
      );
      expect(
        config.installSource(app: 'shop'),
        "DVAccessibilityControls.instance.install(floatingButton: false, app: 'shop', "
        'voice: const DVAccessibilityVoiceConfig(languages: <DVVoiceLanguage>[DVVoiceLanguage.english, DVVoiceLanguage.hausa], '
        'machineTranslated: <DVVoiceLanguage>{DVVoiceLanguage.hausa}), '
        "formerKey: 'shop.display');",
      );
      expect(const DVAccessibilityDefaultControlsConfig(enabled: true).installSource(app: 'shop'),
          "DVAccessibilityControls.instance.install(floatingButton: true, app: 'shop');");
    });
  });

  group('formerKey', () {
    test('names the key the app kept its own settings under', () {
      expect(DVAccessibilityDefaultControlsConfig.parse(<String, Object?>{'formerKey': 'payseal.lowVision'}).formerKey,
          'payseal.lowVision');
    });

    test('must be a plain storage key', () {
      expect(() => DVAccessibilityDefaultControlsConfig.parse(<String, Object?>{'formerKey': '../x'}), throwsArgumentError);
      expect(() => DVAccessibilityDefaultControlsConfig.parse(<String, Object?>{'formerKey': 3}), throwsArgumentError);
    });
  });

  group('round trip', () {
    test('pubspec -> class -> pubspec, with voice and formerKey', () {
      final Map<String, Object?> pubspec = <String, Object?>{
        'accessibility': <String, Object?>{
          'defaultControls': <String, Object?>{
            'floatingButton': false,
            'voice': <String, Object?>{
              'languages': <Object?>['en', 'ibb'],
              'machineTranslated': <Object?>['ibb'],
            },
            'formerKey': 'payseal.lowVision',
          },
        },
      };
      expect(DartvelPubspecConfig.fromPubspec(pubspec).toPubspec(), pubspec);
    });

    test('voice: true round-trips as true', () {
      final Map<String, Object?> pubspec = <String, Object?>{
        'accessibility': <String, Object?>{
          'defaultControls': <String, Object?>{'voice': true},
        },
      };
      expect(DartvelPubspecConfig.fromPubspec(pubspec).toPubspec(), pubspec);
    });
  });

  group('the language catalog', () {
    test('every language has a code, a speech tag, an English and a native name', () {
      for (final DVVoiceLanguage language in DVVoiceLanguage.values) {
        expect(language.code, isNotEmpty);
        expect(language.speechTag, contains(RegExp('^[a-z]{2,3}')));
        expect(language.englishName, isNotEmpty);
        expect(language.nativeName, isNotEmpty);
      }
    });

    test('codes are unique and found by code; an unknown code is English', () {
      final List<String> codes = DVVoiceLanguage.values.map((DVVoiceLanguage l) => l.code).toList();
      expect(codes.toSet().length, codes.length);
      expect(DVVoiceLanguage.fromCode('pcm'), DVVoiceLanguage.pidgin);
      expect(DVVoiceLanguage.fromCode('zz'), DVVoiceLanguage.english);
      expect(DVVoiceLanguage.fromCode(null), DVVoiceLanguage.english);
    });

    test('the name a menu shows: English name, then the native one where it differs', () {
      expect(DVVoiceLanguage.english.displayName, 'English');
      expect(DVVoiceLanguage.yoruba.displayName, 'Yoruba (Yorùbá)');
    });

    test('a device voice speaks a language when its tag starts with the language', () {
      expect(DVVoiceLanguage.yoruba.hasVoiceIn(<String>{'en-US', 'yo_NG'}), isTrue);
      expect(DVVoiceLanguage.igbo.hasVoiceIn(<String>{'en-US'}), isFalse);
      // Pidgin is read by a Nigerian English voice.
      expect(DVVoiceLanguage.pidgin.hasVoiceIn(<String>{'en-NG'}), isTrue);
    });
  });
}
