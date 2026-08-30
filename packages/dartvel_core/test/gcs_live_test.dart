// Google Cloud Storage against a real fake-gcs-server.
//
// The JSON API is unforgiving about one thing in particular: an object name in
// a path must be fully percent-encoded, slashes included. Leave a slash alone
// and the request addresses a different resource that usually exists, so the
// call succeeds and touches the wrong object.
//
// Start one with:
//   docker run -d -p 4443:4443 fsouza/fake-gcs-server \
//     -scheme http -port 4443 -public-host 127.0.0.1:4443
@Tags(<String>['live'])
library;

import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:dartvel_core/src/storage/gcs.dart';
import 'package:test/test.dart';

void main() {
  final String? endpoint = io.Platform.environment['DARTVEL_GCS_ENDPOINT'];
  if (endpoint == null || endpoint.isEmpty) {
    test('skipped: DARTVEL_GCS_ENDPOINT is not set', () {}, skip: true);
    return;
  }

  late GcsFileStorageAdapter storage;
  final String bucket = 'dv-test-${DateTime.now().millisecondsSinceEpoch}';

  setUpAll(() async {
    storage = GcsFileStorageAdapter(bucket: bucket, endpoint: endpoint);
    await storage.createBucket();
  });

  test('an object round-trips', () async {
    await storage.put('greeting.txt', utf8.encode('hello'),
        contentType: 'text/plain');

    expect(utf8.decode(await storage.get('greeting.txt')), 'hello');
    expect(await storage.exists('greeting.txt'), isTrue);
  });

  test('binary content is not mangled', () async {
    // A media upload that goes out as text corrupts anything above 0x7F.
    final Uint8List blob =
        Uint8List.fromList(List<int>.generate(1024, (int i) => i % 256));
    await storage.put('binary.bin', blob);

    expect(await storage.get('binary.bin'), blob);
  });

  test('a nested key keeps its slashes as part of the name', () async {
    // The name is one opaque string containing slashes, not a path. Encoding
    // it wrongly addresses a different object rather than failing.
    const String key = 'a/b/c/deep.txt';
    await storage.put(key, utf8.encode('nested'));

    expect(utf8.decode(await storage.get(key)), 'nested');
    expect(await storage.list(prefix: 'a/b/'), contains(key));
  });

  test('a key with characters that need escaping round-trips', () async {
    const String key = 'odd names/a b+c(d)&e.txt';
    await storage.put(key, utf8.encode('odd'));

    expect(utf8.decode(await storage.get(key)), 'odd');
  });

  test('listing honours a prefix', () async {
    await storage.put('logs/one.txt', utf8.encode('1'));
    await storage.put('logs/two.txt', utf8.encode('2'));
    await storage.put('other/three.txt', utf8.encode('3'));

    final List<String> logs = await storage.list(prefix: 'logs/');

    expect(logs, containsAll(<String>['logs/one.txt', 'logs/two.txt']));
    expect(logs, isNot(contains('other/three.txt')));
  });

  test('a missing object is not found rather than a failure', () async {
    expect(await storage.exists('nothing-here.txt'), isFalse);

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
}
