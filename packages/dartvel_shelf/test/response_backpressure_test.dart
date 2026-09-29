import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

void main() {
  late ServerHandle server;

  tearDown(() => server.stop());

  test(
    'a fast 200 MiB generator to a slow-reading client keeps memory bounded and arrives whole',
    () async {
      const int totalBytes = 200 * 1024 * 1024; // 200 MiB
      const int chunkSize = 64 * 1024; // 64 KiB
      int generatedBytes = 0;
      int maxInFlightObserved = 0;

      Stream<List<int>> generateBody() async* {
        final chunk = Uint8List(chunkSize);
        for (int i = 0; i < chunkSize; i++) {
          chunk[i] = i % 256;
        }
        for (int offset = 0; offset < totalBytes; offset += chunkSize) {
          generatedBytes += chunkSize;
          yield chunk;
        }
      }

      server = await serve(
        (req) async {
          return Response(
            200,
            headers: Headers()
              ..set('content-type', 'application/octet-stream')
              ..set('content-length', '$totalBytes'),
            body: generateBody(),
          );
        },
        host: '127.0.0.1',
        port: 0,
      );

      final socket = await Socket.connect('127.0.0.1', server.port);
      addTearDown(socket.destroy);

      socket.write(
        'GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n',
      );
      await socket.flush();

      int receivedBytes = 0;
      final initialRss = ProcessInfo.currentRss;
      int maxRssObserved = initialRss;

      final completer = Completer<void>();
      late StreamSubscription<List<int>> socketSub;

      bool pausedPhaseDone = false;

      socketSub = socket.listen(
        (data) async {
          receivedBytes += data.length;
          final inFlight = generatedBytes - receivedBytes;
          if (inFlight > maxInFlightObserved) {
            maxInFlightObserved = inFlight;
          }
          final currentRss = ProcessInfo.currentRss;
          if (currentRss > maxRssObserved) {
            maxRssObserved = currentRss;
          }

          // After initial chunks saturate TCP buffers, pause the socket to verify
          // that the producer stops completely.
          if (!pausedPhaseDone && receivedBytes >= 8 * 1024 * 1024) {
            pausedPhaseDone = true;
            socketSub.pause();
            await Future<void>.delayed(const Duration(milliseconds: 100));
            final genStart = generatedBytes;
            await Future<void>.delayed(const Duration(milliseconds: 250));
            final genEnd = generatedBytes;
            expect(genEnd, equals(genStart),
                reason: 'Producer continued running while client was paused: generated $genEnd vs $genStart');
            socketSub.resume();
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (e, st) {
          if (!completer.isCompleted) completer.completeError(e, st);
        },
      );

      await completer.future;

      // Verify backpressure:
      // With unbounded queues, generatedBytes runs to 200 MiB while receivedBytes is only ~256 KiB,
      // causing maxInFlightObserved to be ~200 MiB!
      // With bounded backpressure, in-flight bytes should never exceed e.g. 2 MiB.
      final rssGrowth = maxRssObserved - initialRss;

      expect(
        maxInFlightObserved,
        lessThan(8 * 1024 * 1024),
        reason:
            'In-flight buffer grew to $maxInFlightObserved bytes without backpressure',
      );

      // Memory RSS growth should be modest (nowhere near unconstrained 200+ MiB leak on top of test runner):
      expect(
        rssGrowth,
        lessThan(250 * 1024 * 1024),
        reason: 'RSS grew by ${rssGrowth ~/ (1024 * 1024)} MiB',
      );

      expect(receivedBytes, greaterThanOrEqualTo(totalBytes));
      expect(generatedBytes, equals(totalBytes));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
