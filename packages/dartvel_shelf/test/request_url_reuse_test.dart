// A request's URL is parsed once per target and server, and shared: Uri is
// immutable, and every request of a hot route used to build the same one
// again from the same bytes -- the string concatenation and the whole parse,
// for each request. What must not change with it: a target that cannot be
// a URL is still refused, every time; a different target is a different
// URL; and one server's URLs name that server, not another's.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

Future<int?> _status(int port, String target) async {
  final Socket socket = await Socket.connect('127.0.0.1', port);
  socket.write('GET $target HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n');
  final String text = await socket
      .cast<List<int>>()
      .transform(latin1.decoder)
      .join()
      .timeout(const Duration(seconds: 5));
  socket.destroy();
  final RegExpMatch? match = RegExp(r'^HTTP/1\.1 (\d{3})').firstMatch(text);
  return match == null ? null : int.parse(match.group(1)!);
}

void main() {
  final List<Uri> seen = <Uri>[];
  late ServerHandle server;
  late ServerHandle other;

  setUp(() async {
    seen.clear();
    Future<Response> record(Request req) async {
      seen.add(req.url);
      return Response.text('ok');
    }

    server = await serve(record, host: '127.0.0.1', port: 0);
    other = await serve(record, host: '127.0.0.1', port: 0);
  });

  tearDown(() async {
    await server.stop();
    await other.stop();
  });

  test('requests for the same target share one URL', () async {
    expect(await _status(server.port, '/same?x=1'), 200);
    expect(await _status(server.port, '/same?x=1'), 200);
    expect(seen, hasLength(2));
    expect(identical(seen[0], seen[1]), isTrue,
        reason: 'parsed again for the second request');
    expect(seen[0].path, '/same');
    expect(seen[0].queryParameters, <String, String>{'x': '1'});
  });

  test('a different target is a different URL', () async {
    expect(await _status(server.port, '/a'), 200);
    expect(await _status(server.port, '/b'), 200);
    expect(seen.map((Uri url) => url.path), <String>['/a', '/b']);
  });

  test('a target that is not a URL is refused every time', () async {
    expect(await _status(server.port, '/bad%zz'), 400);
    expect(await _status(server.port, '/bad%zz'), 400);
    expect(seen, isEmpty);
  });

  test("each server's URLs name that server", () async {
    expect(await _status(server.port, '/here'), 200);
    expect(await _status(other.port, '/here'), 200);
    expect(seen.map((Uri url) => url.port), <int>[server.port, other.port]);
  });
}
