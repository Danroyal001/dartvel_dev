// Module Distribution and Trust: publishing, pinning and granting.
//
// Every refusal here is a supply-chain failure that would otherwise be
// silent. The archive parses, a signature checks out against something, the
// version looks like an upgrade -- and the parent runs code nobody reviewed.
// So the tests are mostly about the ways a module gets in that look right: a
// file changed after signing, a new key under an old key id, a signature
// stripped, a revoked key still pinned, a version rolled back, a capability
// nobody granted, and trust read off a field the publisher writes itself.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/doctor/module_check.dart';
import 'package:dartvel_cli/src/module_trust/capabilities.dart';
import 'package:dartvel_cli/src/module_trust/module_lock.dart';
import 'package:dartvel_cli/src/module_trust/module_publish.dart';
import 'package:dartvel_cli/src/module_trust/module_signature.dart';
import 'package:dartvel_cli/src/module_trust/module_trust.dart';
import 'package:dartvel_cli/src/module_trust/package_digest.dart';
import 'package:dartvel_core/dartvel.dart' show dvModuleSigningPublicKey;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final Uint8List publisherKey = Uint8List.fromList(
  List<int>.generate(32, (int i) => i + 1),
);
final Uint8List otherKey = Uint8List.fromList(
  List<int>.generate(32, (int i) => 200 - i),
);

const String _paymentsCode = '''
Future<void> charge() async {
  final String key = DV.Secrets.get('STRIPE_KEY');
  await DV.Http.post('https://api.stripe.com/v1/charges', json: <String, Object?>{'k': key});
}
''';

String modulePubspec({
  String version = '2.1.0',
  String capabilities =
      "      secrets: [STRIPE_KEY]\n      egress: ['api.stripe.com']\n",
}) =>
    'name: acme_payments\n'
    'version: $version\n'
    'dependencies:\n'
    '  dartvel_flutter: ^0.5.0\n'
    'dartvel:\n'
    '  module:\n'
    '    id: payments\n'
    '    capabilities:\n'
    '$capabilities';

const String _grant = '''
      grant:
        secrets: [STRIPE_KEY]
        egress: ['api.stripe.com']
''';

/// A fake of the registry's verified-publisher answer. No network.
class FakePublishers implements DVModulePublisherDirectory {
  FakePublishers(this.answers);

  final Map<String, String?> answers;

  @override
  String? verifiedPublisher(String package) => answers[package];
}

class Fixture {
  Fixture(this.root);

  final Directory root;

  String get path => root.path;
  String get module => p.join(root.path, 'modules', 'payments');

  void writeParent({
    String mount = 'package',
    String grant = _grant,
    String extra = '',
  }) {
    final String source = mount == 'package'
        ? '      package: acme_payments\n'
        : '      source: { path: modules/payments }\n';
    File(p.join(path, 'pubspec.yaml')).writeAsStringSync(
      'name: shopfront\n'
      'dartvel:\n'
      '$extra'
      '  modules:\n'
      '    payments:\n'
      '      mount: /pay\n'
      '$source'
      '$grant',
    );
  }

  void writeModule(String relative, String contents) {
    File(p.join(module, relative))
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);
  }

  DVModulePublishResult publish({
    Uint8List? key,
    String? publisher = 'acme.example',
  }) {
    final DVModulePublishResult result = dvPrepareModulePublish(
      module,
      privateKey: key ?? publisherKey,
      keyId: 'acme-2026',
      publisher: publisher,
    );
    expect(result.ok, isTrue, reason: result.findings.join('\n'));
    return result;
  }

  DVModuleTrustReport evaluate({DVModulePublisherDirectory? publishers}) =>
      dvEvaluateModuleTrust(path, publishers: publishers);

  DVModulePinResult pin({
    DVModulePublisherDirectory? publishers,
    bool allowDowngrade = false,
  }) => dvPinModules(
    path,
    publishers: publishers,
    allowDowngrade: allowDowngrade,
  );

  String get lock => File(p.join(path, dvModuleLockFile)).readAsStringSync();
  set lock(String value) =>
      File(p.join(path, dvModuleLockFile)).writeAsStringSync(value);
}

Fixture fixture({
  String mount = 'package',
  String grant = _grant,
  String code = _paymentsCode,
  String? pubspec,
  String extra = '',
}) {
  final Directory root = Directory.systemTemp.createTempSync(
    'dartvel_modtrust_',
  );
  addTearDown(() => root.deleteSync(recursive: true));
  final Fixture f = Fixture(root)
    ..writeParent(mount: mount, grant: grant, extra: extra);
  f.writeModule('pubspec.yaml', pubspec ?? modulePubspec());
  f.writeModule('lib/payments.dart', code);
  File(p.join(root.path, '.dart_tool', 'package_config.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          <String, Object?>{
            'name': 'acme_payments',
            'rootUri': '../modules/payments',
            'packageUri': 'lib/',
          },
        ],
      }),
    );
  return f;
}

List<String> codes(Iterable<DVModuleTrustFinding> findings) => <String>[
  for (final DVModuleTrustFinding f in findings)
    if (f.code != null) f.code!,
];

List<String> errorCodes(DVModuleTrustReport report) =>
    codes(report.findings.where((DVModuleTrustFinding f) => f.isError));

void main() {
  group('dartvel modules publish', () {
    test('signs the digest of exactly what is on disk', () {
      final Fixture f = fixture();
      final DVModulePublishResult result = f.publish();

      final String document = File(
        p.join(f.module, dvModuleSignatureFile),
      ).readAsStringSync();
      final DVModuleSignature signature = dvVerifyModuleSignature(
        document,
        publicKey: dvModuleSigningPublicKey(publisherKey),
      );
      expect(signature.statement.package, 'acme_payments');
      expect(signature.statement.version, '2.1.0');
      expect(signature.statement.sha256, dvModulePackageDigest(f.module));
      expect(signature.statement.capabilities.items(), <String>[
        'secrets: STRIPE_KEY',
        'egress: api.stripe.com',
      ]);
      expect(signature.statement.publisher, 'acme.example');
      expect(signature.statement.dartvel, '^0.5.0');
      expect(
        result.fingerprint,
        dvModuleKeyFingerprint(dvModuleSigningPublicKey(publisherKey)),
      );
    });

    test('refuses a declared capability the code never uses', () {
      final Fixture f = fixture(
        pubspec: modulePubspec(
          capabilities:
              "      secrets: [STRIPE_KEY]\n      egress: ['api.stripe.com']\n      rawSql: true\n",
        ),
      );
      final DVModulePublishResult result = dvPrepareModulePublish(
        f.module,
        privateKey: publisherKey,
        keyId: 'acme-2026',
      );
      expect(result.ok, isFalse);
      expect(codes(result.findings), contains('DV-MODULE-007'));
      expect(result.findings.join('\n'), contains('rawSql'));
      expect(
        File(p.join(f.module, dvModuleSignatureFile)).existsSync(),
        isFalse,
      );
    });

    test('refuses a capability the code uses and does not declare', () {
      final Fixture f = fixture(
        code:
            "$_paymentsCode\nFuture<void> wipe() => DV.DB.execute('DELETE FROM t');\n",
      );
      final DVModulePublishResult result = dvPrepareModulePublish(
        f.module,
        privateKey: publisherKey,
        keyId: 'acme-2026',
      );
      expect(result.ok, isFalse);
      expect(codes(result.findings), contains('DV-MODULE-007'));
      expect(result.findings.join('\n'), contains('rawSql'));
      expect(
        File(p.join(f.module, dvModuleSignatureFile)).existsSync(),
        isFalse,
      );
    });

    test('refuses a module that opens its own connection', () {
      final Fixture f = fixture(
        code: '$_paymentsCode\nfinal c = HttpClient();\n',
      );
      final DVModulePublishResult result = dvPrepareModulePublish(
        f.module,
        privateKey: publisherKey,
        keyId: 'acme-2026',
      );
      expect(result.ok, isFalse);
      expect(codes(result.findings), contains('DV-MODULE-008'));
    });

    test('refuses a URL built at runtime, which no parent can grant', () {
      final Fixture f = fixture(
        code: '$_paymentsCode\nFuture<void> x(String u) => DV.Http.get(u);\n',
      );
      final DVModulePublishResult result = dvPrepareModulePublish(
        f.module,
        privateKey: publisherKey,
        keyId: 'acme-2026',
      );
      expect(result.ok, isFalse);
      expect(result.findings.join('\n'), contains('runtime'));
    });
  });

  group('the signature', () {
    DVModuleSignedStatement statement() => DVModuleSignedStatement(
      package: 'acme_payments',
      version: '2.1.0',
      sha256: 'a' * 64,
      capabilities: const DVModuleCapabilities(
        egress: <String>{'api.stripe.com'},
      ),
    );

    test('does not verify against another key', () {
      final String document = dvSignModulePackage(
        statement(),
        privateKey: publisherKey,
        keyId: 'k',
      );
      expect(
        () => dvVerifyModuleSignature(
          document,
          publicKey: dvModuleSigningPublicKey(otherKey),
        ),
        throwsA(isA<DVModuleSignatureException>()),
      );
    });

    test('covers the payload bytes: an edited payload does not verify', () {
      final Map<String, Object?> document =
          jsonDecode(
                dvSignModulePackage(
                  statement(),
                  privateKey: publisherKey,
                  keyId: 'k',
                ),
              )
              as Map<String, Object?>;
      final String payload = utf8.decode(
        base64Url.decode(document['payload']! as String),
      );
      document['payload'] = base64Url.encode(
        utf8.encode(payload.replaceFirst('a' * 64, 'b' * 64)),
      );
      expect(
        () => dvVerifyModuleSignature(
          jsonEncode(document),
          publicKey: dvModuleSigningPublicKey(publisherKey),
        ),
        throwsA(isA<DVModuleSignatureException>()),
      );
    });

    test(
      'refuses a signed payload that two parsers could read differently',
      () {
        // A duplicate key: signed as written, and read by jsonDecode as the
        // last value. The signature would cover a statement nobody sees.
        final String canonical = utf8.decode(statement().canonicalBytes());
        final String duplicated = canonical.replaceFirst(
          '"package":"acme_payments"',
          '"package":"acme_payments","package":"evil"',
        );
        expect(duplicated, isNot(canonical));
        final List<int> bytes = utf8.encode(duplicated);
        final String document = jsonEncode(<String, Object?>{
          'format': 'dartvel-module-signature-v1',
          'keyId': 'k',
          'publicKey': dvModuleSigningPublicKey(publisherKey),
          'payload': base64Url.encode(bytes),
          'signature': dvModuleSignBytes(bytes, publisherKey),
        });
        expect(
          () => dvVerifyModuleSignature(
            document,
            publicKey: dvModuleSigningPublicKey(publisherKey),
          ),
          throwsA(isA<DVModuleSignatureException>()),
        );
      },
    );
  });

  group('pinning', () {
    test('a package module that was never pinned does not build', () {
      final Fixture f = fixture()..publish();
      final DVModuleTrustReport report = f.evaluate();
      expect(report.ok, isFalse);
      expect(report.lines().join('\n'), contains('dartvel modules pin'));
    });

    test(
      'pinning records version, digest, key and capabilities, and then builds',
      () {
        final Fixture f = fixture()..publish();
        final DVModulePinResult pinned = f.pin();
        expect(pinned.ok, isTrue, reason: pinned.refused.join('\n'));

        final DVModulePin pin = DVModuleLock.read(
          f.path,
        ).pins['acme_payments']!;
        expect(pin.version, '2.1.0');
        expect(pin.sha256, dvModulePackageDigest(f.module));
        expect(pin.key, dvModuleSigningPublicKey(publisherKey));
        expect(pin.capabilities, <String>['secrets', 'egress']);

        final DVModuleTrustReport report = f.evaluate();
        expect(report.ok, isTrue, reason: report.lines().join('\n'));
      },
    );

    test('an unsigned package module is not pinned', () {
      final Fixture f = fixture();
      final DVModulePinResult pinned = f.pin();
      expect(pinned.ok, isFalse);
      expect(File(p.join(f.path, dvModuleLockFile)).existsSync(), isFalse);
    });

    test('a file changed after pinning is DV-MODULE-004', () {
      final Fixture f = fixture()..publish();
      f.pin();
      f.writeModule(
        'lib/payments.dart',
        '$_paymentsCode\n// harmless-looking\n',
      );
      final DVModuleTrustReport report = f.evaluate();
      expect(report.ok, isFalse);
      expect(errorCodes(report), contains('DV-MODULE-004'));
    });

    test('a file added after pinning is DV-MODULE-004', () {
      final Fixture f = fixture()..publish();
      f.pin();
      f.writeModule('hook/build.dart', 'void main() {}\n');
      expect(errorCodes(f.evaluate()), contains('DV-MODULE-004'));
    });

    test('a lockfile digest is compared whole, not as a prefix', () {
      final Fixture f = fixture()..publish();
      f.pin();
      final String digest = dvModulePackageDigest(f.module);
      f.lock = f.lock.replaceFirst(digest, digest.substring(0, 16));
      expect(f.evaluate().ok, isFalse);
    });

    test('nor case-blind', () {
      final Fixture f = fixture()..publish();
      f.pin();
      final String digest = dvModulePackageDigest(f.module);
      f.lock = f.lock.replaceFirst(digest, digest.toUpperCase());
      expect(f.evaluate().ok, isFalse);
    });

    test('a new key under the same key id is DV-MODULE-005', () {
      final Fixture f = fixture()..publish();
      f.pin();
      f.publish(key: otherKey);
      final DVModuleTrustReport report = f.evaluate();
      expect(report.ok, isFalse);
      expect(errorCodes(report), contains('DV-MODULE-005'));
    });

    test('and the fix is an explicit re-pin', () {
      final Fixture f = fixture()..publish();
      f.pin();
      f.publish(key: otherKey);
      final DVModulePinResult repinned = f.pin();
      expect(repinned.ok, isTrue, reason: repinned.refused.join('\n'));
      expect(repinned.pinned.join('\n'), contains('key changed'));
      expect(f.evaluate().ok, isTrue);
    });

    test('a signature removed after pinning is DV-MODULE-005', () {
      final Fixture f = fixture()..publish();
      f.pin();
      File(p.join(f.module, dvModuleSignatureFile)).deleteSync();
      final DVModuleTrustReport report = f.evaluate();
      expect(report.ok, isFalse);
      expect(errorCodes(report), contains('DV-MODULE-005'));
    });

    test('a revoked key is refused even though it is pinned', () {
      final Fixture f = fixture()..publish();
      f.pin();
      final String fingerprint = dvModuleKeyFingerprint(
        dvModuleSigningPublicKey(publisherKey),
      );
      f.writeParent(extra: '  moduleTrust:\n    revokedKeys: [$fingerprint]\n');
      final DVModuleTrustReport report = f.evaluate();
      expect(report.ok, isFalse);
      expect(errorCodes(report), contains('DV-MODULE-005'));
      expect(
        f.pin().ok,
        isFalse,
        reason: 're-pinning must not launder a revoked key',
      );
    });

    test('an older version than the pin is refused', () {
      final Fixture f = fixture()..publish();
      f.pin();
      f.writeModule('pubspec.yaml', modulePubspec(version: '2.0.9'));
      f.publish();
      final DVModuleTrustReport report = f.evaluate();
      expect(report.ok, isFalse);
      expect(report.lines().join('\n'), contains('older'));
      expect(f.pin().ok, isFalse);
      expect(f.pin(allowDowngrade: true).ok, isTrue);
    });

    test('a prerelease of the pinned version is older, not the same', () {
      final Fixture f = fixture()..publish();
      f.pin();
      f.writeModule('pubspec.yaml', modulePubspec(version: '2.1.0-beta.1'));
      f.publish();
      expect(f.pin().ok, isFalse);
    });

    test('the signed statement must describe the installed package', () {
      // A genuine signature copied from another version of the package.
      final Fixture f = fixture()..publish();
      final String signature = File(
        p.join(f.module, dvModuleSignatureFile),
      ).readAsStringSync();
      f.writeModule('pubspec.yaml', modulePubspec(version: '2.1.1'));
      File(
        p.join(f.module, dvModuleSignatureFile),
      ).writeAsStringSync(signature);
      expect(f.pin().ok, isFalse);
    });

    group('the publisher', () {
      test(
        'is pinned from the registry, never from the module\'s own claim',
        () {
          final Fixture f = fixture()..publish(publisher: 'acme.example');
          f.pin();
          expect(
            DVModuleLock.read(f.path).pins['acme_payments']!.publisher,
            isNull,
            reason:
                'with no registry to ask, the claim is all there is, and '
                'it is written by the publisher',
          );
        },
      );

      test('a claim the registry contradicts is not pinned', () {
        final Fixture f = fixture()..publish(publisher: 'acme.example');
        final DVModulePinResult pinned = f.pin(
          publishers: FakePublishers(<String, String?>{
            'acme_payments': 'someone.else',
          }),
        );
        expect(pinned.ok, isFalse);
        expect(codes(pinned.refused), contains('DV-MODULE-005'));
      });

      test('a publisher that changes after pinning is DV-MODULE-005', () {
        final Fixture f = fixture()..publish(publisher: 'acme.example');
        f.pin(
          publishers: FakePublishers(<String, String?>{
            'acme_payments': 'acme.example',
          }),
        );
        expect(
          DVModuleLock.read(f.path).pins['acme_payments']!.publisher,
          'acme.example',
        );
        final DVModuleTrustReport report = f.evaluate(
          publishers: FakePublishers(<String, String?>{
            'acme_payments': 'takeover.example',
          }),
        );
        expect(report.ok, isFalse);
        expect(errorCodes(report), contains('DV-MODULE-005'));
      });
    });

    test(
      'a pinned capability list that differs from the installed one is DV-MODULE-003',
      () {
        final Fixture f = fixture()..publish();
        f.pin();
        f.lock = f.lock.replaceFirst('[secrets, egress]', '[egress]');
        expect(errorCodes(f.evaluate()), contains('DV-MODULE-003'));
      },
    );
  });

  group('granting at the mount point', () {
    Fixture pinned({
      String grant = _grant,
      String code = _paymentsCode,
      String? pubspec,
    }) {
      final Fixture f = fixture(grant: grant, code: code, pubspec: pubspec)
        ..publish();
      expect(f.pin().ok, isTrue);
      return f;
    }

    test('no grant is no capabilities: DV-MODULE-001 names both sides', () {
      final DVModuleTrustReport report = pinned(grant: '').evaluate();
      expect(report.ok, isFalse);
      final List<DVModuleTrustFinding> ungranted = report.findings
          .where((DVModuleTrustFinding f) => f.code == 'DV-MODULE-001')
          .toList();
      expect(
        ungranted.map((DVModuleTrustFinding f) => f.message).join('\n'),
        allOf(contains('STRIPE_KEY'), contains('api.stripe.com')),
      );
      for (final DVModuleTrustFinding finding in ungranted) {
        expect(finding.message, contains('shopfront'));
        expect(finding.message, contains('payments'));
      }
    });

    test('a parent domain does not grant a subdomain', () {
      final DVModuleTrustReport report = pinned(
        grant: '''
      grant:
        secrets: [STRIPE_KEY]
        egress: ['stripe.com']
''',
      ).evaluate();
      expect(errorCodes(report), contains('DV-MODULE-001'));
    });

    test('a grant beyond what the module asks for is DV-MODULE-003', () {
      final DVModuleTrustReport report = pinned(
        grant: '''
      grant:
        secrets: [STRIPE_KEY]
        egress: ['api.stripe.com']
        rawSql: true
''',
      ).evaluate();
      expect(report.ok, isFalse);
      expect(errorCodes(report), contains('DV-MODULE-003'));
    });

    test('a module that grew a capability does not get it by being upgraded', () {
      final Fixture f = pinned();
      f.writeModule(
        'pubspec.yaml',
        modulePubspec(
          version: '2.2.0',
          capabilities:
              "      secrets: [STRIPE_KEY]\n      egress: ['api.stripe.com']\n      rawSql: true\n",
        ),
      );
      f.writeModule(
        'lib/payments.dart',
        "$_paymentsCode\nFuture<int> wipe() => DV.DB.execute('DELETE FROM t');\n",
      );
      f.publish();
      expect(f.pin().ok, isTrue, reason: 'pinning is identity, not permission');

      final DVModuleTrustReport report = f.evaluate();
      expect(report.ok, isFalse);
      expect(
        errorCodes(report),
        containsAll(<String>['DV-MODULE-003', 'DV-MODULE-001']),
      );
      expect(report.lines().join('\n'), contains('rawSql'));
    });

    test('network: true in a grant grants nothing', () {
      final DVModuleTrustReport report = pinned(
        grant: '''
      grant:
        network: true
''',
      ).evaluate();
      expect(report.ok, isFalse);
      expect(errorCodes(report), contains('DV-MODULE-001'));
    });

    test('a module mounted from source is checked against its grant too', () {
      final Fixture f = fixture(mount: 'source', grant: '');
      final DVModuleTrustReport report = f.evaluate();
      expect(report.ok, isFalse);
      expect(errorCodes(report), contains('DV-MODULE-001'));
    });

    test('a source module that needs nothing and is not signed passes', () {
      // Local composition, which is what every module in the examples is.
      final Fixture f = fixture(
        mount: 'source',
        grant: '',
        code: 'void hello() {}\n',
        pubspec: 'name: acme_payments\nversion: 2.1.0\n',
      );
      final DVModuleTrustReport report = f.evaluate();
      expect(report.ok, isTrue, reason: report.lines().join('\n'));
    });

    test('a source module that opens its own socket is DV-MODULE-008', () {
      final Fixture f = fixture(
        mount: 'source',
        code: '$_paymentsCode\nfinal c = HttpClient();\n',
      );
      expect(errorCodes(f.evaluate()), contains('DV-MODULE-008'));
    });

    test('dartvel doctor --modules fails on what the evaluation refuses', () {
      final DVModuleCheck failing = DVModuleCheck.trust(pinned(grant: '').path);
      expect(failing.ok, isFalse);
      expect(failing.lines.join('\n'), contains('DV-MODULE-001'));

      final DVModuleCheck passing = DVModuleCheck.trust(pinned().path);
      expect(passing.ok, isTrue, reason: passing.lines.join('\n'));
    });
  });

  group('the lockfile', () {
    test('round-trips', () {
      final DVModuleLock lock = DVModuleLock(<String, DVModulePin>{
        'acme_payments': DVModulePin(
          package: 'acme_payments',
          version: '2.1.0',
          sha256: 'f' * 64,
          publisher: 'acme.example',
          key: dvModuleSigningPublicKey(publisherKey),
          capabilities: const <String>['secrets', 'egress'],
        ),
      });
      final Directory dir = Directory.systemTemp.createTempSync(
        'dartvel_modlock_',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      lock.write(dir.path);
      final DVModuleLock read = DVModuleLock.read(dir.path);
      expect(read.problems, isEmpty);
      expect(read.render(), lock.render());
    });

    test('a digest that is not 64 lowercase hex characters is a problem', () {
      final Directory dir = Directory.systemTemp.createTempSync(
        'dartvel_modlock_',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      File(p.join(dir.path, dvModuleLockFile)).writeAsStringSync('''
acme_payments:
  version: 2.1.0
  sha256: 9f2c
  publisher: null
  key: null
  capabilities: []
''');
      expect(
        DVModuleLock.read(dir.path).problems.join('\n'),
        contains('sha256'),
      );
    });
  });
}
