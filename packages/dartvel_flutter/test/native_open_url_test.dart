// An external link off the web: DVNavLink.external, DVLinkOpener.open and
// everything else that reaches dvOpenUrl handed the URL to nothing on a phone
// or desktop, so the tap did nothing at all. Off the web it now goes to the
// platform's `links.open` binding, which Android answers with ACTION_VIEW.
import 'package:dartvel_flutter/dartvel_flutter.dart' hide DVAndroidBindings;
import 'package:dartvel_flutter/src/platform/android/android_bindings_jni.dart' show DVAndroidBindings;
import 'package:dartvel_flutter/src/platform/android/android_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => DVNativeBridge.unregister('links.open'));

  test('off the web dvOpenUrl hands the address to the links.open binding', () async {
    final List<Object?> asked = <Object?>[];
    DVNativeBridge.register('links.open', (Object? arguments) {
      asked.add(arguments);
      return true;
    });
    dvOpenUrl('https://github.com/Danroyal001/dev_launcher/releases/latest', newTab: true);
    await Future<void>.delayed(Duration.zero);
    expect(asked, <Object?>[
      <String, Object?>{'url': 'https://github.com/Danroyal001/dev_launcher/releases/latest'},
    ]);
  });

  test('DVLinkOpener.open reaches the binding too (the funnel every external link uses)', () async {
    final List<Object?> asked = <Object?>[];
    DVNativeBridge.register('links.open', (Object? arguments) {
      asked.add(arguments);
      return true;
    });
    DVLinkOpener.install(dvOpenUrl);
    DVLinkOpener.open('https://dartvel.dev/');
    await Future<void>.delayed(Duration.zero);
    expect(asked, hasLength(1));
  });

  test('with no binding it does nothing and throws nothing', () {
    expect(() => dvOpenUrl('https://dartvel.dev/'), returnsNormally);
  });

  test('a binding that fails is not an exception out of a tap handler', () async {
    DVNativeBridge.register('links.open', (Object? _) => throw StateError('no browser'));
    expect(() => dvOpenUrl('https://dartvel.dev/'), returnsNormally);
    await Future<void>.delayed(Duration.zero);
  });

  group('Android', () {
    test('links.open is a claimed binding', () {
      expect(DVAndroidBindings.implemented, contains('links.open'));
    });

    test('the view intent carries the new-task flag (started from the application Context)', () {
      expect(dvAndroidOpenUrlIntentFlags & 0x10000000, 0x10000000);
    });

    test('only addresses meant for another app are opened, never intent: or file: ones', () {
      for (final String url in <String>['https://dartvel.dev/', 'http://example.com', 'mailto:a@b.c', 'tel:+2348000000000', 'sms:123', 'geo:0,0?q=Uyo', 'market://details?id=x']) {
        expect(dvAndroidOpensUrl(url), isTrue, reason: url);
      }
      for (final String url in <String>['intent://scan/#Intent;scheme=zxing;end', 'file:///data/data/x', 'content://x/y', 'javascript:alert(1)', '/relative/path', '']) {
        expect(dvAndroidOpensUrl(url), isFalse, reason: url);
      }
    });
  });
}
