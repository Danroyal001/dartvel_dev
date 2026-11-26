// `dartvel.accessibility.defaultControls`: the accessibility button and panel every
// Dartvel app can opt into (text size, high contrast, reduced motion).
//
// Two spellings, one value: the pubspec map and a DartvelConfig class. What a
// visitor chooses is kept as one small JSON value, read by the app and by the
// SSR-first head before the first paint, so its shape is pinned here.
import 'package:dartvel_core/config.dart';
import 'package:dartvel_core/dartvel.dart' show dvSsrFirstHead;
import 'package:test/test.dart';

class _ShopConfig extends DartvelConfig {
  const _ShopConfig();

  @override
  DVAccessibilityDefaultControlsConfig get accessibilityDefaultControls =>
      const DVAccessibilityDefaultControlsConfig(enabled: true, floatingButton: false);
}

class _OldShopConfig extends DartvelConfig {
  const _OldShopConfig();

  @override
  // ignore: deprecated_member_use
  DVAccessibilityControlsConfig get accessibilityControls => const DVAccessibilityControlsConfig(enabled: true);
}

void main() {
  group('the pubspec switch', () {
    test('absent means off: no app gets controls it did not ask for', () {
      final DVAccessibilityDefaultControlsConfig config = DVAccessibilityDefaultControlsConfig.parse(null);
      expect(config.enabled, isFalse);
      expect(DVAccessibilityDefaultControlsConfig.fromSection(<String, Object?>{}).enabled, isFalse);
    });

    test('true turns it on with the framework\'s floating button', () {
      final DVAccessibilityDefaultControlsConfig config = DVAccessibilityDefaultControlsConfig.parse(true);
      expect(config.enabled, isTrue);
      expect(config.floatingButton, isTrue);
    });

    test('a map turns it on unless it says enabled: false, and can drop the floating button', () {
      final DVAccessibilityDefaultControlsConfig placed =
          DVAccessibilityDefaultControlsConfig.parse(<String, Object?>{'floatingButton': false});
      expect(placed.enabled, isTrue);
      expect(placed.floatingButton, isFalse);
      expect(DVAccessibilityDefaultControlsConfig.parse(<String, Object?>{'enabled': false}).enabled, isFalse);
    });

    test('is read from dartvel.accessibility, beside the audit waivers', () {
      final DVAccessibilityDefaultControlsConfig config = DVAccessibilityDefaultControlsConfig.fromSection(<String, Object?>{
        'accessibility': <String, Object?>{'defaultControls': true, 'waivers': <Object?>[]},
      });
      expect(config.enabled, isTrue);
    });

    test('a misspelt key is refused, naming it', () {
      expect(
        () => DVAccessibilityDefaultControlsConfig.parse(<String, Object?>{'floatingButon': false}),
        throwsA(isA<ArgumentError>().having((ArgumentError e) => '${e.message}', 'message', contains('floatingButon'))),
      );
    });
  });

  group('config class parity', () {
    final Map<String, Object?> everyField = <String, Object?>{
      'accessibility': <String, Object?>{
        'defaultControls': <String, Object?>{'floatingButton': false},
      },
    };

    test('pubspec -> class -> pubspec is identical', () {
      expect(DartvelPubspecConfig.fromPubspec(everyField).toPubspec(), everyField);
    });

    test('the Dart class serialises to exactly the YAML object', () {
      expect(const _ShopConfig().toPubspec(), everyField);
    });

    test('plain true round-trips as true', () {
      final Map<String, Object?> on = <String, Object?>{
        'accessibility': <String, Object?>{'defaultControls': true},
      };
      expect(DartvelPubspecConfig.fromPubspec(on).toPubspec(), on);
    });

    test('off writes nothing', () {
      expect(DartvelPubspecConfig.fromPubspec(<String, Object?>{}).toPubspec(), isNot(contains('accessibility')));
    });
  });


  // 3.47.16 shipped the key as `controls`; 3.47.18 renamed it `defaultControls`.
  // The old spelling keeps working for one release (the build warns, naming the
  // new key), so a published project never silently loses the panel.
  group('the old `controls` key, for one release', () {
    test('still turns the controls on, with the same shapes', () {
      expect(
        DVAccessibilityDefaultControlsConfig.fromSection(<String, Object?>{
          'accessibility': <String, Object?>{'controls': true},
        }),
        const DVAccessibilityDefaultControlsConfig(enabled: true),
      );
      expect(
        DVAccessibilityDefaultControlsConfig.fromSection(<String, Object?>{
          'accessibility': <String, Object?>{
            'controls': <String, Object?>{'floatingButton': false},
          },
        }),
        const DVAccessibilityDefaultControlsConfig(enabled: true, floatingButton: false),
      );
    });

    test('a misspelling under the old key names the old key it was written under', () {
      expect(
        () => DVAccessibilityDefaultControlsConfig.fromSection(<String, Object?>{
          'accessibility': <String, Object?>{
            'controls': <String, Object?>{'floatingButon': false},
          },
        }),
        throwsA(isA<ArgumentError>().having((ArgumentError e) => e.name, 'name', 'dartvel.accessibility.controls')),
      );
    });

    test('a misspelling under the new key names the new key', () {
      expect(
        () => DVAccessibilityDefaultControlsConfig.parse(<String, Object?>{'floatingButon': false}),
        throwsA(isA<ArgumentError>().having((ArgumentError e) => e.name, 'name', 'dartvel.accessibility.defaultControls')),
      );
    });

    test('both keys at once is refused rather than one silently winning', () {
      expect(
        () => DVAccessibilityDefaultControlsConfig.fromSection(<String, Object?>{
          'accessibility': <String, Object?>{'controls': true, 'defaultControls': false},
        }),
        throwsA(isA<ArgumentError>().having((ArgumentError e) => '${e.message}', 'message', contains('defaultControls'))),
      );
    });

    test('a pubspec on the old key round-trips onto the new one', () {
      expect(
        DartvelPubspecConfig.fromPubspec(<String, Object?>{
          'accessibility': <String, Object?>{'controls': true},
        }).toPubspec(),
        <String, Object?>{
          'accessibility': <String, Object?>{'defaultControls': true},
        },
      );
    });

    test('a config class still overriding accessibilityControls keeps the panel, under the old key so the build warns',
        () {
      expect(const _OldShopConfig().toPubspec(), <String, Object?>{
        'accessibility': <String, Object?>{'controls': true},
      });
    });
  });

  group('what a visitor chose', () {
    test('defaults: standard text, normal contrast, motion as the device asks', () {
      const DVAccessibilitySettings settings = DVAccessibilitySettings();
      expect(settings.textSize, DVTextSize.standard);
      expect(settings.textScale, 1.0);
      expect(settings.highContrast, isFalse);
      expect(settings.reducedMotion, isFalse);
      expect(settings.isDefault, isTrue);
    });

    test('text sizes are 100, 135 and 170 percent', () {
      expect(DVTextSize.values.map((DVTextSize size) => size.scale), <double>[1.0, 1.35, 1.7]);
    });

    test('encodes to the JSON the SSR-first head reads, and back', () {
      const DVAccessibilitySettings settings =
          DVAccessibilitySettings(textSize: DVTextSize.large, highContrast: true, reducedMotion: true);
      final String stored = settings.encode();
      expect(stored, contains('"textScale":1.35'));
      expect(stored, contains('"highContrast":true'));
      expect(stored, contains('"reducedMotion":true'));
      expect(DVAccessibilitySettings.decode(stored), settings);
    });

    test('anything unreadable is the default, so a broken value never stops a page', () {
      for (final String? stored in <String?>[null, '', '{', '[1]', '{"textScale":"huge"}']) {
        expect(DVAccessibilitySettings.decode(stored), const DVAccessibilitySettings(), reason: '$stored');
      }
      expect(DVAccessibilitySettings.decode('{"textScale":1.7}').textSize, DVTextSize.larger);
    });

    test('the storage key is the one the head script reads', () {
      expect(dvAccessibilityStorageKey, 'dartvel.accessibility');
    });
  });

  group('the SSR-first head', () {
    String head({required bool controls}) => dvSsrFirstHead(
          background: '#FFFFFF',
          darkBackground: '#000000',
          accent: '#047857',
          accessibilityControls: controls,
        );

    test('without the controls it is what it was', () {
      expect(head(controls: false), isNot(contains(dvAccessibilityStorageKey)));
    });

    test('with them, reads the visitor\'s settings before the first paint', () {
      final String withControls = head(controls: true);
      expect(withControls, contains('localStorage'));
      expect(withControls, contains(dvAccessibilityStorageKey));
      // Large text and high contrast are drawn as the reading column in the
      // visitor's settings (the captured layout is the default settings').
      expect(withControls, contains('data-dv-plain'));
      expect(withControls, contains('data-dv-contrast'));
      expect(withControls, contains('--dv-text-scale'));
      // The operating system's settings count too.
      expect(withControls, contains('prefers-contrast: more'));
      // And reduced motion skips the handover's fade.
      expect(withControls, contains('data-dv-reduce-motion'));
      // The script runs before the document style it feeds.
      expect(withControls.indexOf(dvAccessibilityStorageKey), lessThan(withControls.indexOf(dvSsrFirstMarkerForTests)));
    });
  });
}

/// The SSR-first style element's marker.
const String dvSsrFirstMarkerForTests = 'id="dartvel-ssr-first"';

// The captured layout and the theme for uncaptured pages are the app drawn at
// the default settings: a visitor with large text or high contrast gets the
// reading column in their settings instead (see the gate test in
// ssr_first_layout_test.dart and ssr_first_theme_test.dart).
