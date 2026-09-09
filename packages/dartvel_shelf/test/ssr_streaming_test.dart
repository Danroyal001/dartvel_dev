// `dartvel.web.server.streaming` on the server that actually ships.
//
// The declaration travels the whole way -- parsed from pubspec.yaml, written
// into dartvel_routes.json, parsed back out by this server -- and then the
// value was dropped on the floor. Only the preview server split the page, so
// a project that turned streaming on saw the head go out first while
// developing and saw the whole document buffered once deployed. The point of
// the setting is that a crawler and a person get the title before the data
// is done, and buffering removes exactly that.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVPageData, DVPageRequest;
import 'package:dartvel_core/http.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _shell =
    '<!DOCTYPE html>\n<html><head><title>Shell</title></head><body><div id="app"></div></body></html>';

/// A built web-server directory, with whatever `dartvel.web.server` said.
Directory site({bool streaming = false}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_stream_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'index.html')).writeAsStringSync(_shell);
  File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(
    <String, Object?>{
      'siteUrl': 'https://example.com',
      'server': <String, Object?>{'streaming': streaming},
      'routes': <String, Object?>{
        '/products/:id': <String, Object?>{'title': 'A product'},
      },
    },
  ));
  return root;
}

Future<Response> get(Directory root, String path) => handleSsrFallback(
      Request(
        method: 'GET',
        url: Uri.parse('http://example.com$path'),
        headers: Headers(),
        bodyStream: const Stream<List<int>>.empty(),
      ),
      root.path,
      pageData: (DVPageRequest request) => DVPageData(
        title: 'Product ${request.params['id']}',
        text: const <String>['In stock'],
      ),
    );

Future<List<String>> chunks(Response response) async => <String>[
      for (final List<int> chunk in await response.body!.stream.toList())
        utf8.decode(chunk),
    ];

void main() {
  test('declared streaming puts the head on the wire ahead of the body',
      () async {
    final Response response = await get(site(streaming: true), '/products/5');

    final List<String> parts = await chunks(response);
    // More than one write, or nothing was gained: a single-chunk body is
    // buffered and sent whole.
    expect(parts.length, greaterThan(1));
    expect(parts.first, endsWith('</head>'));
    expect(parts.first, contains('<title>Product 5</title>'));
    // And the rest still arrives, so the page is whole.
    expect(parts.join(), contains('In stock'));
  });

  test('the response is marked as a stream, so the runtime sends it in pieces',
      () async {
    // The FFI layer buffers everything it is not told is a stream, so the
    // split above would be undone one layer down without this.
    final Response response = await get(site(streaming: true), '/products/5');

    expect(response.isStream, isTrue);
  });

  test('without the declaration the page is one buffered response', () async {
    final Response response = await get(site(), '/products/5');

    expect(response.isStream, isFalse);
    expect(await chunks(response), hasLength(1));
  });
}
