// The federated module manifest, and the parent's decision to trust it.
//
// A federated module is built and deployed by somebody else and mounted into
// this application's routes. The manifest is the only thing standing between
// "a partner ships a section of our site" and "a partner ships whatever they
// like into our site", so the interesting part of this file is not that a
// good manifest is accepted. It is the manifests that are refused.
//
// Each of these is a real way to get a fraudulent module mounted, and each
// one is quiet: the manifest parses, the signature checks out against
// *something*, and the parent mounts it.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// A P-256 key the tests sign with. Any 32 bytes below the curve order do.
final Uint8List _publisherKey = Uint8List.fromList(<int>[
  for (var i = 1; i <= 32; i++) i,
]);
final Uint8List _otherKey = Uint8List.fromList(<int>[
  for (var i = 33; i <= 64; i++) i,
]);

DVModuleManifest storeManifest({
  String version = '1.2.0',
  List<String> routes = const <String>['/products', '/products/:id'],
  Set<String> capabilities = const <String>{},
  String? requiresParent,
}) =>
    DVModuleManifest(
      id: 'store',
      version: version,
      routes: routes,
      capabilities: capabilities,
      assets: const <String, String>{'logo': 'assets/logo.png'},
      shell: 'inherit',
      auth: 'federated',
      theme: 'override',
      data: 'schema-isolated',
      publicFunctions: const <String>['store.checkout'],
      publicSignals: const <String>['store.cartCount'],
      requiresParent: requiresParent,
      location: 'https://store.example.com/module',
    );

String signedBy(DVModuleManifest manifest, Uint8List key, {String keyId = 'publisher'}) =>
    dvSignModuleManifest(manifest, privateKey: key, keyId: keyId);

Map<String, String> get trusted => <String, String>{
      'publisher': dvModuleSigningPublicKey(_publisherKey),
    };

void main() {
  group('a manifest the parent should mount', () {
    test('is accepted, and comes back with what it declared', () {
      final String document = signedBy(storeManifest(), _publisherKey);

      final DVModuleTrust trust = dvVerifyModuleManifest(
        document,
        trustedKeys: trusted,
        expectedId: 'store',
      );

      expect(trust.accepted, isTrue, reason: trust.reason);
      expect(trust.manifest!.version, '1.2.0');
      expect(trust.manifest!.routes, contains('/products/:id'));
      expect(trust.manifest!.auth, 'federated');
    });
  });

  group('a manifest the parent must refuse', () {
    test('one whose routes were edited after signing', () {
      // The whole attack: the signature is real, the module is real, and one
      // line of the document is not the line that was signed.
      final String document = signedBy(storeManifest(), _publisherKey);
      final Map<String, Object?> tampered =
          jsonDecode(document) as Map<String, Object?>;
      final Map<String, Object?> manifest =
          tampered['manifest']! as Map<String, Object?>;
      manifest['routes'] = <String>['/products', '/admin/**'];

      final DVModuleTrust trust = dvVerifyModuleManifest(
        jsonEncode(tampered),
        trustedKeys: trusted,
        expectedId: 'store',
      );

      expect(trust.accepted, isFalse);
      expect(trust.reason, contains('signature'));
    });

    test('one signed by a key the parent does not trust', () {
      // A perfectly valid signature, by somebody else.
      final String document = signedBy(storeManifest(), _otherKey);

      final DVModuleTrust trust = dvVerifyModuleManifest(
        document,
        trustedKeys: trusted,
        expectedId: 'store',
      );

      expect(trust.accepted, isFalse);
      expect(trust.reason, contains('signature'));
    });

    test('one signed by a trusted key under a different key id', () {
      // The document names which key signed it, and a document that names a
      // key it was not signed with must not be checked against the one it
      // names and passed on some other key.
      final String document = signedBy(storeManifest(), _otherKey, keyId: 'publisher');

      final DVModuleTrust trust = dvVerifyModuleManifest(
        document,
        trustedKeys: trusted,
        expectedId: 'store',
      );

      expect(trust.accepted, isFalse);
    });

    test('a module that is not the one being mounted', () {
      // Genuinely signed, genuinely a Dartvel module, and not the module the
      // parent asked for -- which is how a partner's staging module gets
      // mounted where their production one belongs.
      final String document = signedBy(storeManifest(), _publisherKey);

      final DVModuleTrust trust = dvVerifyModuleManifest(
        document,
        trustedKeys: trusted,
        expectedId: 'documentation',
      );

      expect(trust.accepted, isFalse);
      expect(trust.reason, contains('store'));
    });

    test('an older version than the parent has already accepted', () {
      // A rollback: an old manifest is signed just as validly as a new one,
      // so replaying yesterday's is how a fixed vulnerability comes back.
      final String document = signedBy(storeManifest(version: '1.1.0'), _publisherKey);

      final DVModuleTrust trust = dvVerifyModuleManifest(
        document,
        trustedKeys: trusted,
        expectedId: 'store',
        lastAcceptedVersion: '1.2.0',
      );

      expect(trust.accepted, isFalse);
      expect(trust.reason, contains('1.1.0'));
    });

    test('the same version again is fine; it is the same module', () {
      final String document = signedBy(storeManifest(version: '1.2.0'), _publisherKey);

      final DVModuleTrust trust = dvVerifyModuleManifest(
        document,
        trustedKeys: trusted,
        expectedId: 'store',
        lastAcceptedVersion: '1.2.0',
      );

      expect(trust.accepted, isTrue, reason: trust.reason);
    });

    test('one whose routes collide with the parent\'s own', () {
      // Mounted, the module would answer for a route the parent already
      // serves, and whichever wins, one of them silently stops working.
      final String document = signedBy(storeManifest(), _publisherKey);

      final DVModuleTrust trust = dvVerifyModuleManifest(
        document,
        trustedKeys: trusted,
        expectedId: 'store',
        mountPath: '/store',
        parentRoutes: const <String>{'/store/products'},
      );

      expect(trust.accepted, isFalse);
      expect(trust.reason, contains('/store/products'));
    });

    test('one needing a capability this target does not have', () {
      final String document = signedBy(
        storeManifest(capabilities: const <String>{'camera', 'bluetooth'}),
        _publisherKey,
      );

      final DVModuleTrust trust = dvVerifyModuleManifest(
        document,
        trustedKeys: trusted,
        expectedId: 'store',
        targetCapabilities: const <String>{'camera'},
      );

      expect(trust.accepted, isFalse);
      expect(trust.reason, contains('bluetooth'));
    });

    test('one needing a newer parent than this one', () {
      final String document =
          signedBy(storeManifest(requiresParent: '>=3.0.0'), _publisherKey);

      final DVModuleTrust trust = dvVerifyModuleManifest(
        document,
        trustedKeys: trusted,
        expectedId: 'store',
        parentVersion: '2.9.0',
      );

      expect(trust.accepted, isFalse);
      expect(trust.reason, contains('3.0.0'));
    });

    test('a document that is not a manifest at all', () {
      for (final String rubbish in <String>['', 'null', '{}', '{"manifest":1}', 'not json']) {
        final DVModuleTrust trust = dvVerifyModuleManifest(
          rubbish,
          trustedKeys: trusted,
          expectedId: 'store',
        );
        expect(trust.accepted, isFalse, reason: 'accepted "$rubbish"');
        expect(trust.reason, isNotEmpty);
      }
    });

    test('a manifest with no trusted keys at all is refused, not waved through', () {
      // An empty allowlist is a parent that has not been configured, and the
      // safe reading of "no keys are trusted" is that none are.
      final String document = signedBy(storeManifest(), _publisherKey);

      final DVModuleTrust trust = dvVerifyModuleManifest(
        document,
        trustedKeys: const <String, String>{},
        expectedId: 'store',
      );

      expect(trust.accepted, isFalse);
    });
  });

  group('the signature covers the whole manifest', () {
    test('every field, one at a time', () {
      // A signature over some of the fields is worse than none, because the
      // fields it leaves out are the ones nobody thinks to check.
      final String document = signedBy(storeManifest(), _publisherKey);
      final Map<String, Object?> parsed =
          jsonDecode(document) as Map<String, Object?>;
      final Map<String, Object?> manifest =
          (parsed['manifest']! as Map<String, Object?>);

      for (final String field in manifest.keys.toList()) {
        final Map<String, Object?> edited =
            jsonDecode(document) as Map<String, Object?>;
        final Map<String, Object?> body =
            edited['manifest']! as Map<String, Object?>;
        body[field] = body[field] is List
            ? <String>['/tampered']
            : body[field] is Map
                ? <String, String>{'tampered': 'yes'}
                : 'tampered';

        final DVModuleTrust trust = dvVerifyModuleManifest(
          jsonEncode(edited),
          trustedKeys: trusted,
          expectedId: 'store',
        );

        expect(trust.accepted, isFalse, reason: 'editing "$field" was accepted');
      }
    });
  });
}
