// `dartvel.push` in pubspec.yaml. Read strictly for the reason crash settings
// are: every setting has a safe default, so a misspelt key or a wrong type
// would be replaced by one and look exactly like a setting that was honoured.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

// A valid P-256 public key: 0x04 then 64 bytes, as base64url.
final String vapidKey = dvWebPushBase64Encode(<int>[4, ...List<int>.filled(64, 9)]);

const Map<String, Object?> fcm = <String, Object?>{
  'projectId': 'demo-project',
  'appId': '1:1234567890:android:abc123',
  'apiKey': 'AIzaSyDemoKeyDemoKeyDemoKeyDemoKey000',
  'senderId': '1234567890',
};

void main() {
  test('nothing declared is nothing wired', () {
    final DVPushConfig config = DVPushConfig.parse(null);
    expect(config.isDeclared, isFalse);
    expect(config.web, isNull);
    expect(config.androidFcm, isNull);
  });

  test('web takes the VAPID public key the browser subscribes with', () {
    final DVPushConfig config = DVPushConfig.parse(<String, Object?>{
      'web': <String, Object?>{'vapidPublicKey': vapidKey},
    });
    expect(config.isDeclared, isTrue);
    expect(config.web!.vapidPublicKey, vapidKey);
  });

  test('web: true without a key is refused, naming what to add', () {
    expect(
      () => DVPushConfig.parse(<String, Object?>{'web': true}),
      throwsA(isA<ArgumentError>().having(
          (ArgumentError e) => e.name, 'name', contains('vapidPublicKey'))),
    );
  });

  test('a key that is not a P-256 public point is refused', () {
    for (final String bad in <String>[
      'not base64 !!',
      dvWebPushBase64Encode(<int>[1, 2, 3]),
      dvWebPushBase64Encode(<int>[2, ...List<int>.filled(64, 1)]),
    ]) {
      expect(
        () => DVPushConfig.parse(<String, Object?>{
          'web': <String, Object?>{'vapidPublicKey': bad},
        }),
        throwsA(isA<ArgumentError>()),
        reason: bad,
      );
    }
  });

  test('android.fcm carries the four public client identifiers', () {
    final DVPushConfig config = DVPushConfig.parse(<String, Object?>{
      'android': <String, Object?>{'fcm': fcm},
    });
    expect(config.androidFcm!.projectId, 'demo-project');
    expect(config.androidFcm!.appId, '1:1234567890:android:abc123');
    expect(config.androidFcm!.apiKey, startsWith('AIza'));
    expect(config.androidFcm!.senderId, '1234567890');
  });

  test('each android.fcm identifier is required', () {
    for (final String missing in fcm.keys) {
      expect(
        () => DVPushConfig.parse(<String, Object?>{
          'android': <String, Object?>{
            'fcm': <String, Object?>{...fcm}..remove(missing),
          },
        }),
        throwsA(isA<ArgumentError>().having((ArgumentError e) => e.name,
            'name', contains(missing))),
        reason: missing,
      );
    }
  });

  test('a service account or private key in pubspec is refused', () {
    // The server credential belongs in Secrets. A pubspec is committed.
    expect(
      () => DVPushConfig.parse(<String, Object?>{
        'android': <String, Object?>{
          'fcm': <String, Object?>{...fcm, 'privateKey': 'x'},
        },
      }),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('an unknown key is refused, naming the ones that exist', () {
    expect(
      () => DVPushConfig.parse(<String, Object?>{'wbe': true}),
      throwsA(isA<ArgumentError>().having(
          (ArgumentError e) => '${e.message}', 'message', contains('web'))),
    );
    expect(
      () => DVPushConfig.parse(<String, Object?>{'ios': <String, Object?>{}}),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('wrong types are refused', () {
    expect(() => DVPushConfig.parse('yes'), throwsA(isA<ArgumentError>()));
    expect(() => DVPushConfig.parse(<String, Object?>{'android': true}),
        throwsA(isA<ArgumentError>()));
    expect(
      () => DVPushConfig.parse(<String, Object?>{
        'android': <String, Object?>{'fcm': <String, Object?>{...fcm, 'projectId': 7}},
      }),
      throwsA(isA<ArgumentError>()),
    );
  });
}
