// Patch signatures, checked against openssl rather than against ourselves.
//
// The updater verifies with ring's RSA_PKCS1_2048_8192_SHA256 over the ASCII
// of the hex hash, base64 signature, base64 DER PKCS#1 public key
// (shorebirdtech/updater library/src/cache/signing.rs). A signer and verifier
// written together can agree on the wrong thing -- signing the raw digest,
// say, or encoding the key as SubjectPublicKeyInfo -- and every device would
// then refuse every patch. So each direction is checked against openssl,
// which is what Shorebird's own docs tell people to make keys and signatures
// with.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

late Directory dir;

String _openssl(List<String> args, {List<int>? stdinBytes}) {
  final ProcessResult result = Process.runSync(
    'openssl',
    args,
    workingDirectory: dir.path,
    stdoutEncoding: null,
  );
  if (result.exitCode != 0) {
    fail('openssl ${args.join(' ')} failed: ${result.stderr}');
  }
  return base64.encode(result.stdout as List<int>);
}

String _read(String name) => File('${dir.path}/$name').readAsStringSync();

void main() {
  final bool haveOpenssl =
      Process.runSync('openssl', <String>['version']).exitCode == 0;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('dv_patch_signing_');
    if (!haveOpenssl) return;
    _openssl(<String>['genrsa', '-out', 'private.pem', '2048']);
    _openssl(<String>[
      'rsa',
      '-in',
      'private.pem',
      '-pubout',
      '-out',
      'public.pem',
    ]);
    _openssl(<String>[
      'rsa',
      '-in',
      'private.pem',
      '-traditional',
      '-out',
      'private_pkcs1.pem',
    ]);
    _openssl(<String>['genrsa', '-out', 'other.pem', '2048']);
    _openssl(<String>['genrsa', '-out', 'small.pem', '1024']);
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  final String hash = sha256.convert(utf8.encode('out.vmcode')).toString();

  test('the release key is the DER PKCS#1 key openssl writes', () {
    final String expected = _openssl(<String>[
      'rsa',
      '-in',
      'public.pem',
      '-pubin',
      '-RSAPublicKey_out',
      '-outform',
      'DER',
    ]);
    expect(DVPatchSigning.releasePublicKey(_read('public.pem')), expected);
    expect(DVPatchSigning.releasePublicKeyOf(_read('private.pem')), expected);
  }, skip: haveOpenssl ? false : 'openssl is not installed');

  test('a signature openssl makes of the hex hash verifies', () {
    File('${dir.path}/hash.txt').writeAsStringSync(hash);
    final String signature = _openssl(<String>[
      'dgst',
      '-sha256',
      '-sign',
      'private.pem',
      'hash.txt',
    ]);
    final String key = DVPatchSigning.releasePublicKey(_read('public.pem'));
    expect(DVPatchSigning.verifyHash(hash, signature, key), isTrue);
  }, skip: haveOpenssl ? false : 'openssl is not installed');

  test('a signature made here verifies with openssl, from either private key '
      'format', () {
    for (final String name in <String>['private.pem', 'private_pkcs1.pem']) {
      final String signature = DVPatchSigning.signHash(hash, _read(name));
      File('${dir.path}/hash.txt').writeAsStringSync(hash);
      File('${dir.path}/sig.bin').writeAsBytesSync(base64.decode(signature));
      final ProcessResult verified = Process.runSync('openssl', <String>[
        'dgst',
        '-sha256',
        '-verify',
        'public.pem',
        '-signature',
        'sig.bin',
        'hash.txt',
      ], workingDirectory: dir.path);
      expect(verified.exitCode, 0, reason: '$name: ${verified.stdout}');
    }
  }, skip: haveOpenssl ? false : 'openssl is not installed');

  test('a signature of another hash, or by another key, does not verify', () {
    final String key = DVPatchSigning.releasePublicKey(_read('public.pem'));
    final String signature = DVPatchSigning.signHash(hash, _read('private.pem'));
    final String otherHash = sha256.convert(utf8.encode('other')).toString();
    expect(DVPatchSigning.verifyHash(otherHash, signature, key), isFalse);
    final String forged = DVPatchSigning.signHash(hash, _read('other.pem'));
    expect(DVPatchSigning.verifyHash(hash, forged, key), isFalse);
    expect(DVPatchSigning.verifyHash(hash, 'not base64!', key), isFalse);
  }, skip: haveOpenssl ? false : 'openssl is not installed');

  test('a key the updater cannot verify with is refused before signing', () {
    expect(
      () => DVPatchSigning.signHash(hash, _read('small.pem')),
      throwsA(isA<DVPatchSigningException>()),
      reason: 'ring refuses RSA keys under 2048 bits',
    );
    expect(
      () => DVPatchSigning.signHash('not-a-hash', _read('private.pem')),
      throwsA(isA<DVPatchSigningException>()),
    );
    expect(
      () => DVPatchSigning.privateKey(_read('public.pem')),
      throwsA(isA<DVPatchSigningException>()),
    );
  }, skip: haveOpenssl ? false : 'openssl is not installed');
}
