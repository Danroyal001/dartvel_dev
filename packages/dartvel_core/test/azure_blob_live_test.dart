// Azure Blob Storage against a real Azurite, not a fake.
//
// The signature is the whole adapter: everything else is an HTTP verb. A
// Shared Key signature can only be checked by something that verifies it the
// way Azure does, so a test that signs and then verifies with the same code
// proves nothing. Azurite rejects a wrong signature with 403, which is the
// assertion worth having.
//
// Start one with:
//   docker run -d -p 10000:10000 mcr.microsoft.com/azure-storage/azurite \
//     azurite-blob --blobHost 0.0.0.0
@Tags(<String>['live'])
library;

import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:dartvel_core/src/storage/azure_blob.dart';
import 'package:test/test.dart';

/// The well-known Azurite development credentials. Not a secret: they are
/// published in Microsoft's documentation and only ever reach a local emulator.
const String account = 'devstoreaccount1';
const String accountKey =
    'Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==';

void main() {
  // Same convention as the other live suites: an emulator that is not
  // configured is a skip with a reason, never a silent pass and never a
  // failure on a machine that was never going to have one.
  final String? endpoint = io.Platform.environment['DARTVEL_AZURITE'];
  if (endpoint == null || endpoint.isEmpty) {
    test('skipped: DARTVEL_AZURITE is not set', () {}, skip: true);
    return;
  }

  late AzureBlobFileStorageAdapter storage;
  final String container = 'dv-test-${DateTime.now().millisecondsSinceEpoch}';

  setUpAll(() async {
    storage = AzureBlobFileStorageAdapter(
      account: account,
      accountKey: accountKey,
      container: container,
      endpoint: endpoint,
    );
    await storage.createContainer();
  });

  test('a signature Azurite accepts, which is the only proof there is',
      () async {
    // 403 here means the string-to-sign is wrong somewhere: a header out of
    // order, a length that should have been blank, an unescaped path.
    await storage.put('greeting.txt', utf8.encode('hello'),
        contentType: 'text/plain');

    expect(await storage.exists('greeting.txt'), isTrue);
  });

  test('what went up comes back byte for byte', () async {
    final Uint8List blob =
        Uint8List.fromList(List<int>.generate(4096, (int i) => i % 256));
    await storage.put('binary.bin', blob);

    expect(await storage.get('binary.bin'), blob);
  });

  test('a key with characters that must be escaped still round-trips',
      () async {
    // The canonicalised resource is built from the path, so an unescaped
    // space or plus signs a different string than the one sent.
    const String key = 'nested/a b+c(d).txt';
    await storage.put(key, utf8.encode('escaped'));

    expect(utf8.decode(await storage.get(key)), 'escaped');
    expect(await storage.exists(key), isTrue);
  });

  test('listing sees what was written, and honours a prefix', () async {
    await storage.put('logs/one.txt', utf8.encode('1'));
    await storage.put('logs/two.txt', utf8.encode('2'));
    await storage.put('other/three.txt', utf8.encode('3'));

    final List<String> logs = await storage.list(prefix: 'logs/');

    expect(logs, containsAll(<String>['logs/one.txt', 'logs/two.txt']));
    expect(logs, isNot(contains('other/three.txt')));
  });

  test('a missing object is not found rather than a failure', () async {
    expect(await storage.exists('nothing-here.txt'), isFalse);

    // The distinction matters: callers branch on it.
    await expectLater(
      storage.get('nothing-here.txt'),
      throwsA(
        isA<Object>().having(
          (Object e) => (e as dynamic).isNotFound,
          'isNotFound',
          isTrue,
        ),
      ),
    );
  });

  test('delete removes it, and deleting again is not an error', () async {
    await storage.put('temp.txt', utf8.encode('x'));
    await storage.delete('temp.txt');

    expect(await storage.exists('temp.txt'), isFalse);
    await storage.delete('temp.txt');
  });

  test('a wrong key is refused, so the signature is really being checked',
      () async {
    // Without this the suite would pass against a server that ignored
    // authentication entirely.
    final AzureBlobFileStorageAdapter wrong = AzureBlobFileStorageAdapter(
      account: account,
      accountKey: base64.encode(utf8.encode('not-the-real-key-0123456789')),
      container: container,
      endpoint: endpoint,
    );

    await expectLater(
      wrong.put('denied.txt', utf8.encode('x')),
      throwsA(
        isA<Object>().having(
          (Object e) => (e as dynamic).statusCode,
          'statusCode',
          403,
        ),
      ),
    );
  });
}
