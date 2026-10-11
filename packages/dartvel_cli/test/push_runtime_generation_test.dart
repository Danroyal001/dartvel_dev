// The generated runtime's push wiring: which targets get a provider, with
// what key, and nothing at all for a project that declared no push. Wiring a
// provider a project never asked for would start a timer and a Firebase
// lookup in every application; leaving it out of one that did would build,
// register nothing, and receive nothing.
import 'package:dartvel_cli/src/generators/push_runtime.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVPushConfig, dvWebPushBase64Encode;
import 'package:test/test.dart';

final String key = dvWebPushBase64Encode(<int>[4, ...List<int>.filled(64, 9)]);

DVPushConfig config({bool web = false, bool android = false}) =>
    DVPushConfig.parse(<String, Object?>{
      if (web) 'web': <String, Object?>{'vapidPublicKey': key},
      if (android)
        'android': <String, Object?>{
          'fcm': <String, Object?>{
            'projectId': 'p',
            'appId': '1:1:android:a',
            'apiKey': 'k',
            'senderId': '1',
          },
        },
    });

void main() {
  test('a project with no push gets no code at all', () {
    final DVPushConfig none = DVPushConfig.parse(null);
    expect(dvPushRuntimeImports(none), isEmpty);
    expect(dvPushRuntimeCall(none), isEmpty);
    expect(dvPushRuntimeFunction(none), isEmpty);
  });

  test('web wires the provider with the VAPID public key, on web only', () {
    final String fn = dvPushRuntimeFunction(config(web: true));
    expect(fn, contains("vapidPublicKey: '$key'"));
    expect(fn, contains('kIsWeb'));
    expect(fn, isNot(contains('TargetPlatform.android')));
    expect(dvPushRuntimeCall(config(web: true)), contains('startDartvelPush();'));
    expect(dvPushRuntimeImports(config(web: true)),
        contains('DVDevicePushProvider'));
    expect(dvPushRuntimeImports(config(web: true)), contains('PushNotifications'));
  });

  test('android wires the provider on Android only, with no key', () {
    final String fn = dvPushRuntimeFunction(config(android: true));
    expect(fn, contains('TargetPlatform.android'));
    expect(fn, isNot(contains('vapidPublicKey: \'')));
  });

  test('both targets are wired, each behind its own platform test', () {
    final String fn = dvPushRuntimeFunction(config(web: true, android: true));
    expect(fn, contains('kIsWeb'));
    expect(fn, contains('TargetPlatform.android'));
  });

  test('asks for no permission: that is the application calling it from a tap',
      () {
    final String fn = dvPushRuntimeFunction(config(web: true, android: true));
    expect(fn, isNot(contains('PushNotifications.requestPermission(')));
    expect(fn, isNot(contains('permissions.request')));
    expect(fn, contains('PushNotifications.initialize'));
  });

  test('a key with a quote in it cannot escape the string literal', () {
    // Not reachable through DVPushConfig (the key must decode as base64url),
    // but the generator must not rely on that.
    final String fn = dvPushRuntimeFunctionFor(
        webKey: "a'b\$c", android: false);
    expect(fn, contains(r"vapidPublicKey: 'a\'b\$c'"));
  });
}
