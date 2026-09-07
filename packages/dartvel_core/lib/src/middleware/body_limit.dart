/// The largest body a route will read.
///
/// `DVMiddlewares.bodyLimit` and `DVMiddlewares.uploadLimit` were declared on
/// the annotation and implemented nowhere, so a route that asked for a limit
/// got none and would read whatever it was handed. They are the two keys
/// that cannot be a middleware in the ordinary sense: the chain runs around
/// the handler, and by the time it has anything to say the body has already
/// been read. A limit that arrives after the read is not a limit.
///
/// So this is enforced where the reading happens -- in the generated request
/// prelude -- and the annotation decides whether the check is emitted at all.
///
/// Two numbers rather than one because they answer different questions. A
/// JSON body is small and something megabytes long is a mistake or an
/// attack; an upload is large on purpose, and holding it to the same figure
/// would refuse the feature.
library;

import 'dart:async';
import 'dart:typed_data';

/// Bytes a request body may be when a route declares `bodyLimit`.
const int dvDefaultBodyLimitBytes = 1024 * 1024;

/// Bytes a multipart upload may be when a route declares `uploadLimit`.
const int dvDefaultUploadLimitBytes = 16 * 1024 * 1024;

/// Limits an application can move.
///
/// Static, and read when the request is handled rather than captured, so a
/// deployment that raises the upload size does not have to rebuild.
class DVBodyLimits {
  static int body = dvDefaultBodyLimitBytes;
  static int upload = dvDefaultUploadLimitBytes;

  /// Test-only: back to the numbers above.
  static void reset() {
    body = dvDefaultBodyLimitBytes;
    upload = dvDefaultUploadLimitBytes;
  }
}

/// Whether a declared `Content-Length` is already over [limit].
///
/// The cheap half. A sender that announces the size is refused before a byte
/// is read, which is the difference between rejecting a request and
/// receiving it first.
///
/// A header that is missing, not a number, or negative is not a refusal: it
/// is no information, and the read below is what bounds those.
bool dvDeclaredTooLarge({required String? contentLength, required int limit}) {
  if (contentLength == null) return false;
  final int? declared = int.tryParse(contentLength.trim());
  if (declared == null || declared < 0) return false;
  return declared > limit;
}

/// Reads [stream] up to [limit] bytes, or null when it is longer.
///
/// Stops at the first byte past the limit rather than reading to the end and
/// measuring, because reading to the end is the thing being prevented. The
/// subscription is cancelled, so a sender that keeps writing is dropped
/// rather than served.
Future<Uint8List?> dvReadCapped(Stream<List<int>> stream, int limit) async {
  final List<Uint8List> chunks = <Uint8List>[];
  int total = 0;
  final Completer<Uint8List?> done = Completer<Uint8List?>();
  late StreamSubscription<List<int>> sub;

  sub = stream.listen(
    (List<int> chunk) {
      if (done.isCompleted) return;
      total += chunk.length;
      if (total > limit) {
        done.complete(null);
        sub.cancel();
        return;
      }
      chunks.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
    },
    onError: (Object error, StackTrace stack) {
      if (!done.isCompleted) done.completeError(error, stack);
    },
    onDone: () {
      if (done.isCompleted) return;
      final Uint8List out = Uint8List(total);
      int offset = 0;
      for (final Uint8List chunk in chunks) {
        out.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      done.complete(out);
    },
    cancelOnError: true,
  );

  return done.future;
}

/// What a refused body is told.
///
/// The limit is in it. A 413 with no number leaves somebody guessing at what
/// would have been accepted, and the number is not a secret -- it is the
/// contract.
String dvTooLargeMessage(int limit) =>
    'Request body too large. This endpoint accepts at most $limit bytes.';
