// The dev client's trust and compatibility rules, below any transport.
//
// A dev client is a shell on somebody's phone that loads whatever a
// `dartvel dev` server hands it. The failures that matter are the quiet ones:
// a bundle from another machine on the same network that renders perfectly,
// a bundle that needs a plugin the shell was built without and fails only
// when somebody taps the button that calls it, and a rebuilt bundle that the
// idempotent apply takes for the one it already has.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Map<String, Object?> _pages(String text) => <String, Object?>{
  'pages': <Object?>[
    <String, Object?>{'route': '/about', 'title': text},
  ],
};

Uri _link({
  String server = 'https://192.168.1.20:8787',
  String branch = 'feature/checkout',
  String? key,
  String? token,
}) {
  return Uri(
    scheme: 'dartvel-dev',
    host: 'pair',
    queryParameters: <String, String>{
      'server': server,
      'branch': branch,
      if (key != null) 'key': key,
      if (token != null) 'token': token,
    },
  );
}

void main() {
  final DVDevClientSigner signer = DVDevClientSigner.generate();
  const DVDevClientManifest shell = DVDevClientManifest(
    target: 'android',
    bindings: <String>['dartvel_flutter@0.4.0', 'plugin:jni'],
  );

  group('a sealed bundle', () {
    test('opens with the key it was sealed with', () {
      final String envelope = signer.seal(
        bundle: _pages('Hello'),
        channel: 'feature/checkout',
        requires: shell,
        sequence: 7,
      );

      final DVSignedBundle opened = DVSignedBundle.open(
        envelope,
        publicKey: signer.publicKey,
      );

      expect(opened.channel, 'feature/checkout');
      expect(opened.sequence, 7);
      expect(opened.requires?.bindings, shell.bindings);
      expect(
        (opened.bundle['pages']! as List).single,
        containsPair('title', 'Hello'),
      );
      // The version is the content, so a rebuild can never be mistaken for
      // the bundle the device already has.
      expect(
        opened.bundle['version'],
        dvDevClientBundleVersion(_pages('Hello')),
      );
    });

    test('from another machine is refused, however well formed', () {
      // The attack the pairing exists for: somebody else on the office
      // network running their own `dartvel dev` and pointing it at the phone.
      final DVDevClientSigner other = DVDevClientSigner.generate();
      final String envelope = other.seal(bundle: _pages('Injected'));

      expect(
        () => DVSignedBundle.open(envelope, publicKey: signer.publicKey),
        throwsA(
          isA<DVSignedBundleException>().having(
            (DVSignedBundleException e) => e.message,
            'message',
            contains('signature'),
          ),
        ),
      );
    });

    test('with its payload altered is refused', () {
      final Map<String, Object?> envelope =
          (jsonDecode(signer.seal(bundle: _pages('Original'))) as Map)
              .cast<String, Object?>();
      final String payload = utf8.decode(
        base64Url.decode(base64Url.normalize('${envelope['payload']}')),
      );
      envelope['payload'] = base64Url
          .encode(utf8.encode(payload.replaceFirst('Original', 'Tampered')))
          .replaceAll('=', '');

      expect(
        () => DVSignedBundle.open(
          jsonEncode(envelope),
          publicKey: signer.publicKey,
        ),
        throwsA(isA<DVSignedBundleException>()),
      );
    });

    test('a plain unsigned page bundle is refused rather than applied', () {
      // The shape OTA page bundles have always had on the wire. A shell that
      // accepted it would be the development tool that skips the check.
      final String unsigned = jsonEncode(<String, Object?>{
        'version': '1.0.0',
        ..._pages('Unsigned'),
      });

      expect(
        () => DVSignedBundle.open(unsigned, publicKey: signer.publicKey),
        throwsA(
          isA<DVSignedBundleException>().having(
            (DVSignedBundleException e) => e.message,
            'message',
            contains('not signed'),
          ),
        ),
      );
    });

    test('a payload with a duplicated key is refused', () {
      // One parser reads the first value and another the last; the signature
      // covers bytes that mean two different things.
      const String payload =
          '{"format":"dartvel-bundle-v1","bundle":{"version":"a","pages":[]},'
          '"bundle":{"version":"b","pages":[]}}';
      final String envelope = jsonEncode(<String, Object?>{
        'format': dvSignedBundleFormat,
        'payload': base64Url.encode(utf8.encode(payload)).replaceAll('=', ''),
        'signature': base64Url
            .encode(signer.sign(utf8.encode(payload)))
            .replaceAll('=', ''),
      });

      expect(
        () => DVSignedBundle.open(envelope, publicKey: signer.publicKey),
        throwsA(
          isA<DVSignedBundleException>().having(
            (DVSignedBundleException e) => e.message,
            'message',
            contains('canonical'),
          ),
        ),
      );
    });

    test('whose version does not match its content is refused', () {
      // A server that stamped a fixed version would have every edit after the
      // first taken for the bundle already applied, and the phone would keep
      // showing the first one without a word.
      final String envelope = signer.seal(
        bundle: <String, Object?>{..._pages('Edited'), 'version': 'dev'},
      );

      expect(
        () => DVSignedBundle.open(
          envelope,
          publicKey: signer.publicKey,
          requireContentVersion: true,
        ),
        throwsA(
          isA<DVSignedBundleException>().having(
            (DVSignedBundleException e) => e.message,
            'message',
            contains('version'),
          ),
        ),
      );
    });
  });

  group('the content version', () {
    test('is the same for the same content in any key order', () {
      final Map<String, Object?> reordered = <String, Object?>{
        'pages': <Object?>[
          <String, Object?>{'title': 'Hello', 'route': '/about'},
        ],
      };
      expect(
        dvDevClientBundleVersion(_pages('Hello')),
        dvDevClientBundleVersion(reordered),
      );
    });

    test('changes when any page changes', () {
      expect(
        dvDevClientBundleVersion(_pages('Hello')),
        isNot(dvDevClientBundleVersion(_pages('Hello!'))),
      );
    });

    test('ignores a version field already present', () {
      expect(
        dvDevClientBundleVersion(<String, Object?>{
          ..._pages('Hello'),
          'version': 'anything',
        }),
        dvDevClientBundleVersion(_pages('Hello')),
      );
    });
  });

  group('the binding manifest', () {
    test('a bundle needing only what the shell has loads', () {
      final DVDevClientRefusal? refusal = dvDevClientCompatibility(
        shell: shell,
        bundle: const DVDevClientManifest(
          target: 'android',
          bindings: <String>['plugin:jni'],
        ),
      );
      expect(refusal, isNull);
    });

    test(
      'a binding the shell lacks refuses with DV-DEVCLIENT-002 naming it',
      () {
        final DVDevClientRefusal? refusal = dvDevClientCompatibility(
          shell: shell,
          bundle: const DVDevClientManifest(
            target: 'android',
            bindings: <String>[
              'dartvel_flutter@0.4.0',
              'plugin:camera',
              'plugin:jni',
              'plugin:nfc_manager',
            ],
          ),
        );

        expect(refusal, isNotNull);
        expect(refusal!.code, 'DV-DEVCLIENT-002');
        expect(DVDiagnostics.find(refusal.code)?.level, 'error');
        // Every one, not the first: rebuilding the shell for one and finding
        // the next is two rebuilds.
        expect(refusal.missing, <String>[
          'plugin:camera',
          'plugin:nfc_manager',
        ]);
        expect(refusal.message, contains('plugin:camera'));
        expect(refusal.message, contains('plugin:nfc_manager'));
      },
    );

    test('a different runtime version is a missing binding, not a match', () {
      final DVDevClientRefusal? refusal = dvDevClientCompatibility(
        shell: shell,
        bundle: const DVDevClientManifest(
          target: 'android',
          bindings: <String>['dartvel_flutter@0.5.0', 'plugin:jni'],
        ),
      );
      expect(refusal?.missing, <String>['dartvel_flutter@0.5.0']);
    });

    test('a bundle resolved for another target is refused', () {
      // The plugin lists are per platform. An iOS manifest compared against
      // an Android shell can agree by accident and still call a missing
      // native.
      final DVDevClientRefusal? refusal = dvDevClientCompatibility(
        shell: shell,
        bundle: const DVDevClientManifest(
          target: 'ios',
          bindings: <String>['plugin:jni'],
        ),
      );
      expect(refusal?.code, 'DV-DEVCLIENT-002');
      expect(refusal?.message, contains('ios'));
    });

    test('round-trips, sorted and without duplicates', () {
      final DVDevClientManifest parsed = DVDevClientManifest.fromJson(
        const DVDevClientManifest(
          target: 'android',
          bindings: <String>['plugin:b', 'plugin:a', 'plugin:b'],
        ).toJson(),
      );
      expect(parsed.bindings, <String>['plugin:a', 'plugin:b']);
      expect(parsed.target, 'android');
    });

    test('a manifest with no target is refused', () {
      expect(
        () => DVDevClientManifest.fromJson(<String, Object?>{
          'bindings': <Object?>['plugin:jni'],
        }),
        throwsFormatException,
      );
    });
  });

  group('pairing', () {
    final String key = base64Url.encode(signer.publicKey).replaceAll('=', '');
    final String token = DVDevClientPairing.newToken();

    test('a link round-trips', () {
      final DVDevClientPairing pairing = DVDevClientPairing(
        server: Uri.parse('https://192.168.1.20:8787'),
        branch: 'feature/checkout',
        publicKey: signer.publicKey,
        token: token,
      );

      final DVDevClientPairing parsed = DVDevClientPairing.parse(pairing.link);

      expect(parsed.server, Uri.parse('https://192.168.1.20:8787'));
      expect(parsed.branch, 'feature/checkout');
      expect(parsed.publicKey, signer.publicKey);
      expect(parsed.token, token);
      expect(parsed.bundleUri('android').path, '/_dartvel/dev-client/bundle');
      expect(parsed.bundleUri('android').queryParameters['target'], 'android');
    });

    test('a link with no key is refused: it could not verify anything', () {
      expect(
        () => DVDevClientPairing.parse(_link(token: token)),
        throwsFormatException,
      );
    });

    test('a link with no token is refused', () {
      expect(
        () => DVDevClientPairing.parse(_link(key: key)),
        throwsFormatException,
      );
    });

    test('a guessable token is refused', () {
      expect(
        () => DVDevClientPairing.parse(_link(key: key, token: 'abc123')),
        throwsFormatException,
      );
    });

    test('a key that is not a P-256 point is refused', () {
      final String bogus = base64Url
          .encode(Uint8List(65)..[0] = 4)
          .replaceAll('=', '');
      expect(
        () => DVDevClientPairing.parse(_link(key: bogus, token: token)),
        throwsFormatException,
      );
    });

    test('a server that is not http or https is refused', () {
      expect(
        () => DVDevClientPairing.parse(
          _link(server: 'file:///etc', key: key, token: token),
        ),
        throwsFormatException,
      );
    });

    test('a link of another scheme is refused', () {
      final Uri other = _link(key: key, token: token).replace(scheme: 'https');
      expect(() => DVDevClientPairing.parse(other), throwsFormatException);
    });

    test('tokens are fresh each time', () {
      expect(
        DVDevClientPairing.newToken(),
        isNot(DVDevClientPairing.newToken()),
      );
    });

    test('a presented token must match exactly', () {
      expect(DVDevClientPairing.tokenMatches(token, token), isTrue);
      expect(DVDevClientPairing.tokenMatches('${token}x', token), isFalse);
      expect(
        DVDevClientPairing.tokenMatches(
          token.replaceRange(0, 1, token[0] == 'A' ? 'B' : 'A'),
          token,
        ),
        isFalse,
      );
      expect(DVDevClientPairing.tokenMatches('', token), isFalse);
      expect(DVDevClientPairing.tokenMatches(null, token), isFalse);
    });
  });
}
