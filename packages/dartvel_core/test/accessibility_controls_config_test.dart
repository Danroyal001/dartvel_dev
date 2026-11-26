// `dartvel.accessibility.controls`: the accessibility button and panel every
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
  DVAccessibilityControlsConfig get accessibilityControls =>
      const DVAccessibilityControlsConfig(enabled: true, floatingButton: false);
}

void main() {
  group('the pubspec switch', () {
    test('absent means off: no app gets controls it did not ask for', () {
      final DVAccessibilityControlsConfig config = DVAccessibilityControlsConfig.parse(null);
      expect(config.enabled, isFalse);
      expect(DVAccessibilityControlsConfig.fromSection(<String, Object?>{}).enabled, isFalse);
    });

    test('true turns it on with the framework\'s floating button', () {
      final DVAccessibilityControlsConfig config = DVAccessibilityControlsConfig.parse(true);
      expect(config.enabled, isTrue);
      expect(config.floatingButton, isTrue);
    });

    test('a map turns it on unless it says enabled: false, and can drop the floating button', () {
      final DVAccessibilityControlsConfig placed =
          DVAccessibilityControlsConfig.parse(<String, Object?>{'floatingButton': false});
      expect(placed.enabled, isTrue);
      expect(placed.floatingButton, isFalse);
      expect(DVAccessibilityControlsConfig.parse(<String, Object?>{'enabled': false}).enabled, isFalse);
    });

    test('is read from dartvel.accessibility, beside the audit waivers', () {
      final DVAccessibilityControlsConfig config = DVAccessibilityControlsConfig.fromSection(<String, Object?>{
        'accessibility': <String, Object?>{'controls': true, 'waivers': <Object?>[]},
      });
      expect(config.enabled, isTrue);
    });

    test('a misspelt key is refused, naming it', () {
      expect(
        () => DVAccessibilityControlsConfig.parse(<String, Object?>{'floatingButon': false}),
        throwsA(isA<ArgumentError>().having((ArgumentError e) => '${e.message}', 'message', contains('floatingButon'))),
      );
    });
  });

  group('config class parity', () {
    final Map<String, Object?> everyField = <String, Object?>{
      'accessibility': <String, Object?>{
        'controls': <String, Object?>{'floatingButton': false},
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
        'accessibility': <String, Object?>{'controls': true},
      };
      expect(DartvelPubspecConfig.fromPubspec(on).toPubspec(), on);
    });

    test('off writes nothing', () {
      expect(DartvelPubspecConfig.fromPubspec(<String, Object?>{}).toPubspec(), isNot(contains('accessibility')));
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
