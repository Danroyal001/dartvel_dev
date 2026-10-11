// The VAPID identity comes from Secrets, in the format `web-push
// generate-vapid-keys` prints: unpadded base64url, a 32-byte private scalar
// and a 65-byte uncompressed public key. The browser pins the public half at
// subscribe time, so the server key and the key given to the client must be
// the same pair or every subscription silently dies on the next send.
import 'dart:convert';
import 'dart:math';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late DVWebPushKeyPair keys;
  late DVSecretsState saved;

  setUp(() {
    saved = DVSecrets.captureState();
    keys = DVWebPushKeyPair.generate(Random(11));
  });
  tearDown(() => DVSecrets.restoreState(saved));

  void configure({bool subject = true, String? privateKey}) {
    DVSecrets.configure(<String, String>{
      'VAPID_PRIVATE_KEY':
          privateKey ?? dvWebPushBase64Encode(keys.privateKey),
      if (subject) 'VAPID_SUBJECT': 'mailto:ops@example.test',
    });
  }

  test('builds the provider from the private key and subject in Secrets', () {
    configure();
    final WebPushProvider provider = WebPushProvider.fromSecrets();
    expect(provider.vapidKeys.privateKey, keys.privateKey);
    expect(provider.vapidKeys.publicKey, keys.publicKey);
    expect(provider.subject, 'mailto:ops@example.test');
  });

  test('the public key is derived, so it cannot disagree with the private one',
      () {
    configure();
    expect(WebPushProvider.fromSecrets().vapidPublicKey,
        dvWebPushBase64Encode(keys.publicKey));
  });

  test('a message sent through it is signed with the key from Secrets',
      () async {
    configure();
    DVHttpRequest? captured;
    final DVWebPushKeyPair browser = DVWebPushKeyPair.generate(Random(5));
    final String subscription = jsonEncode(<String, Object?>{
      'endpoint': 'https://push.example.test/s/1',
      'keys': <String, String>{
        'p256dh': dvWebPushBase64Encode(browser.publicKey),
        'auth': dvWebPushBase64Encode(List<int>.generate(16, (int i) => i)),
      },
    });
    await WebPushProvider.fromSecrets(transport: (DVHttpRequest request) async {
      captured = request;
      return const DVHttpResponse(statusCode: 201, body: '');
    }).send(subscription, const DVNotificationMessage(title: 't', body: 'b'));

    final String header = captured!.headers['authorization']!;
    final String token =
        RegExp(r't=([^,]+),').firstMatch(header)!.group(1)!;
    expect(DVWebPushVapid.verify(token, keys.publicKey), isTrue);
    expect(header, contains('k=${dvWebPushBase64Encode(keys.publicKey)}'));
  });

  test('a missing private key is named, not defaulted', () {
    expect(() => WebPushProvider.fromSecrets(),
        throwsA(isA<DVSecretNotFoundException>()));
  });

  test('a missing subject is named: push services need a contact', () {
    configure(subject: false);
    expect(() => WebPushProvider.fromSecrets(),
        throwsA(isA<DVSecretNotFoundException>()));
  });

  test('a private key of the wrong length is refused with a reason', () {
    configure(privateKey: dvWebPushBase64Encode(List<int>.filled(31, 7)));
    expect(
      () => WebPushProvider.fromSecrets(),
      throwsA(isA<ArgumentError>().having(
          (ArgumentError e) => '${e.message}', 'message', contains('32 bytes'))),
    );
  });

  test('the private key is redacted from log text once it has been read', () {
    configure();
    WebPushProvider.fromSecrets();
    expect(dvRedactSecrets('boom ${dvWebPushBase64Encode(keys.privateKey)}'),
        isNot(contains(dvWebPushBase64Encode(keys.privateKey))));
  });
}
