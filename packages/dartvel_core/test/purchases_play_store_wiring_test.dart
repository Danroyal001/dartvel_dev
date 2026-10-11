// How a project turns on Google Play: a pubspec block for what is not secret,
// DV Secrets for what is, and the real transport underneath.
//
// Each of these was a silent failure. With no transport the adapter threw on
// the first verification; with no push audience every Real-time Developer
// Notification was refused and a refund never reached the ledger; and a
// service account key echoed into an error message is a key in a ticket.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

String fixture(String name) =>
    File('test/fixtures/play_store/$name').readAsStringSync();

String serviceAccountJson() => jsonEncode(<String, Object?>{
      'type': 'service_account',
      'project_id': 'example-project',
      'private_key_id': 'abc123',
      'private_key': fixture('service_account_test_key.pem'),
      'client_email': 'play@example.iam.gserviceaccount.com',
      'client_id': '1234567890',
      'token_uri': 'https://oauth2.googleapis.com/token',
    });

void main() {
  tearDown(() {
    DVSecrets.reset();
    const DVHttp().unfake();
  });

  group('dartvel.purchases.play', () {
    test('reads the three settings', () {
      final DVPlayStoreConfig config = DVPlayStoreConfig.parse(<String, Object?>{
        'packageName': 'com.example.app',
        'pushAudience': 'https://example.com/_dartvel/purchases/notifications/play',
        'pushServiceAccount': 'push@example.iam.gserviceaccount.com',
      });
      expect(config.packageName, 'com.example.app');
      expect(config.pushAudience,
          'https://example.com/_dartvel/purchases/notifications/play');
      expect(config.pushServiceAccount, 'push@example.iam.gserviceaccount.com');
    });

    test('refuses a key it does not know, naming it', () {
      expect(
          () => DVPlayStoreConfig.parse(<String, Object?>{
                'packageName': 'com.example.app',
                'pushAudiance': 'x',
              }),
          throwsA(isA<ArgumentError>().having((ArgumentError e) => '${e.message}',
              'message', contains('pushAudiance'))));
    });

    test('needs a package name', () {
      expect(() => DVPlayStoreConfig.parse(<String, Object?>{}),
          throwsA(isA<ArgumentError>()));
    });

    test('is absent when the project declares purchases without it', () {
      expect(DVPlayStoreConfig.maybeParse(null), isNull);
    });
  });

  group('DVPlayStoreAdapter.fromSecrets', () {
    const DVPlayStoreConfig config = DVPlayStoreConfig(
      packageName: 'com.example.app',
      pushAudience: 'https://example.com/_dartvel/purchases/notifications/play',
      pushServiceAccount: 'push@example.iam.gserviceaccount.com',
    );

    test('builds from the whole service account file', () {
      DVSecrets.configure(
          <String, String>{'PLAY_SERVICE_ACCOUNT_JSON': serviceAccountJson()});
      final DVPlayStoreAdapter adapter = DVPlayStoreAdapter.fromSecrets(config);
      expect(adapter.packageName, 'com.example.app');
      expect(adapter.pushAudience, config.pushAudience);
      expect(adapter.pushServiceAccountEmail, config.pushServiceAccount);
    });

    test('builds from an email and a key kept apart', () {
      DVSecrets.configure(<String, String>{
        'PLAY_SERVICE_ACCOUNT_EMAIL': 'play@example.iam.gserviceaccount.com',
        'PLAY_SERVICE_ACCOUNT_KEY': fixture('service_account_test_key.pem'),
      });
      expect(DVPlayStoreAdapter.fromSecrets(config), isA<DVPlayStoreAdapter>());
    });

    test('fails closed when no credential exists, naming the secret', () {
      expect(
          () => DVPlayStoreAdapter.fromSecrets(config),
          throwsA(isA<StateError>().having((StateError e) => e.message,
              'message', contains('PLAY_SERVICE_ACCOUNT_JSON'))));
    });

    test('a damaged file is refused without repeating any of it', () {
      const String key = 'SUPERSECRETKEYMATERIAL-1234567890';
      DVSecrets.configure(<String, String>{
        'PLAY_SERVICE_ACCOUNT_JSON':
            '{"client_email":"a@b.c","private_key":"$key"',
      });
      Object? thrown;
      try {
        DVPlayStoreAdapter.fromSecrets(config);
      } on Object catch (error) {
        thrown = error;
      }
      expect(thrown, isNotNull);
      expect('$thrown', isNot(contains(key)));
    });

    test('a key that is not a PEM is refused without repeating it', () {
      const String key = 'NOT-A-PEM-BUT-SECRET-1234567890';
      DVSecrets.configure(<String, String>{
        'PLAY_SERVICE_ACCOUNT_JSON': jsonEncode(<String, Object?>{
          'client_email': 'a@b.c',
          'private_key': key,
        }),
      });
      Object? thrown;
      try {
        DVPlayStoreAdapter.fromSecrets(config);
      } on Object catch (error) {
        thrown = error;
      }
      expect(thrown, isNotNull);
      expect('$thrown', isNot(contains(key)));
    });

    test('a service account file for another kind of account is refused', () {
      DVSecrets.configure(<String, String>{
        'PLAY_SERVICE_ACCOUNT_JSON': jsonEncode(<String, Object?>{
          'type': 'authorized_user',
          'client_email': 'a@b.c',
          'private_key': fixture('service_account_test_key.pem'),
        }),
      });
      expect(() => DVPlayStoreAdapter.fromSecrets(config),
          throwsA(isA<StateError>()));
    });

    test('push settings may come from secrets when the pubspec leaves them out',
        () {
      DVSecrets.configure(<String, String>{
        'PLAY_SERVICE_ACCOUNT_JSON': serviceAccountJson(),
        'PLAY_PUSH_AUDIENCE': 'https://example.com/play',
        'PLAY_PUSH_SERVICE_ACCOUNT': 'push@example.iam.gserviceaccount.com',
      });
      final DVPlayStoreAdapter adapter = DVPlayStoreAdapter.fromSecrets(
          const DVPlayStoreConfig(packageName: 'com.example.app'));
      expect(adapter.pushAudience, 'https://example.com/play');
      expect(adapter.pushServiceAccountEmail,
          'push@example.iam.gserviceaccount.com');
    });
  });

  group('the default transport', () {
    test('reaches Google through DV.Http and nowhere else', () async {
      final DVHttpFake fake = const DVHttp().fake(<String, DVHttpStub>{
        'oauth2.googleapis.com': DVHttpStub.json(
            <String, Object?>{'access_token': 'ya29.test', 'expires_in': 3600}),
        'androidpublisher.googleapis.com': DVHttpStub.json(<String, Object?>{
          'purchaseState': 0,
          'purchaseTimeMillis': '1760000000000',
          'orderId': 'GPA.1',
          'acknowledgementState': 1,
        }),
      });
      DVSecrets.configure(
          <String, String>{'PLAY_SERVICE_ACCOUNT_JSON': serviceAccountJson()});
      final DVPlayStoreAdapter adapter = DVPlayStoreAdapter.fromSecrets(
          const DVPlayStoreConfig(packageName: 'com.example.app'));

      final DVStoreTransaction transaction = await adapter.verifyReceipt(
          jsonEncode(<String, Object?>{
            'purchaseToken': 'tok',
            'productId': 'coins',
            'type': 'inapp',
          }));
      expect(transaction.storeProductId, 'coins');
      expect(fake.calls.map((DVHttpCall call) => call.url.host).toSet(),
          <String>{'oauth2.googleapis.com', 'androidpublisher.googleapis.com'});
      final DVHttpCall api = fake.calls.last;
      expect(api.headers['authorization'], 'Bearer ya29.test');
    });
  });
}
