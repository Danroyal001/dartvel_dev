// The largest body a route will read.
//
// bodyLimit and uploadLimit were declared on DVMiddlewares and implemented
// nowhere, so a route that asked for a limit got none and would read
// whatever it was handed. They are the two keys that cannot be an ordinary
// middleware: the chain runs around the handler, and by the time it has
// anything to say the body has already been read. A limit that arrives after
// the read is not a limit.
import 'dart:async';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Stream<List<int>> _chunks(List<int> sizes) async* {
  for (final int size in sizes) {
    yield Uint8List(size);
  }
}

void main() {
  setUp(DVBodyLimits.reset);
  tearDown(DVBodyLimits.reset);

  group('a declared length', () {
    test('over the limit is refused before a byte is read', () {
      // The cheap half, and the one that matters: a sender that announces
      // the size is turned away rather than received first.
      expect(
        dvDeclaredTooLarge(contentLength: '2000', limit: 1000),
        isTrue,
      );
    });

    test('at the limit is allowed', () {
      expect(dvDeclaredTooLarge(contentLength: '1000', limit: 1000), isFalse);
    });

    test('absent is not a refusal', () {
      // A chunked request declares nothing. Refusing those would refuse a
      // legitimate shape; the capped read is what bounds them.
      expect(dvDeclaredTooLarge(contentLength: null, limit: 1000), isFalse);
    });

    test('unreadable is not a refusal either', () {
      // No information is not evidence of a large body, and a header nobody
      // can parse must not decide the request.
      expect(dvDeclaredTooLarge(contentLength: 'lots', limit: 1000), isFalse);
      expect(dvDeclaredTooLarge(contentLength: '-5', limit: 1000), isFalse);
      expect(dvDeclaredTooLarge(contentLength: '  12  ', limit: 1000), isFalse);
    });
  });

  group('reading with a cap', () {
    test('a body inside the limit comes back whole', () async {
      final Uint8List? read = await dvReadCapped(_chunks(<int>[10, 20]), 100);

      expect(read, isNotNull);
      expect(read!.length, 30);
    });

    test('a body exactly at the limit is allowed', () async {
      final Uint8List? read = await dvReadCapped(_chunks(<int>[50, 50]), 100);

      expect(read, isNotNull);
      expect(read!.length, 100);
    });

    test('one byte over is refused', () async {
      expect(await dvReadCapped(_chunks(<int>[50, 51]), 100), isNull);
    });

    test('it stops rather than reading to the end and measuring', () async {
      // Reading to the end is the thing being prevented. A stream that never
      // finishes has to be dropped at the limit, not waited on -- so this
      // completes at all only if the subscription is cancelled.
      var delivered = 0;
      Stream<List<int>> forever() async* {
        while (true) {
          delivered++;
          yield Uint8List(64);
          await Future<void>.delayed(Duration.zero);
        }
      }

      final Uint8List? read = await dvReadCapped(forever(), 128).timeout(
        const Duration(seconds: 5),
      );

      expect(read, isNull);
      // Three chunks of 64 is the first that exceeds 128, so it stopped
      // there rather than going on.
      expect(delivered, lessThan(10));
    });

    test('an error on the stream is not silently an empty body', () async {
      // Swallowing it would hand the handler nothing and look like a request
      // that carried nothing.
      Stream<List<int>> broken() async* {
        yield Uint8List(4);
        throw const FormatException('the connection went');
      }

      await expectLater(
        dvReadCapped(broken(), 100),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('what it says', () {
    test('the refusal carries the number', () {
      // A 413 with no number leaves somebody guessing at what would have
      // been accepted, and the number is the contract rather than a secret.
      expect(dvTooLargeMessage(2048), contains('2048'));
    });
  });

  group('the limits themselves', () {
    test('an upload is allowed to be larger than a body', () {
      // They answer different questions. A JSON body of several megabytes is
      // a mistake or an attack; an upload is large on purpose, and one
      // figure for both would refuse the feature.
      expect(dvDefaultUploadLimitBytes, greaterThan(dvDefaultBodyLimitBytes));
    });

    test('an application can move them', () {
      DVBodyLimits.upload = 99;
      expect(DVBodyLimits.upload, 99);
      DVBodyLimits.reset();
      expect(DVBodyLimits.upload, dvDefaultUploadLimitBytes);
    });
  });
}
