// A page whose data failed answers 500 with the application's status page.
//
// Error, Empty, and Loading States: "a 500 is not a stack trace in front of a
// customer, and the detail a developer needs goes to the log while the
// visitor gets a sentence." A page data resolver that threw used to escape
// the page handler, and the server answered with a line of plain text and no
// shell, so the application never loaded to say anything. The answer is now
// the shell with the 500 route's captured page in it, the status is 500, and
// the error goes to the log -- never into the body.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVPageRequest;
import 'package:dartvel_core/http.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _shell = '<!DOCTYPE html><html><head><title>Acme</title></head>'
    '<body><div id="app"></div></body></html>';

Directory site({bool statusPage = true}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_500_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'index.html')).writeAsStringSync(_shell);
  File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(
    <String, Object?>{
      'routes': <String, Object?>{
        '/': <String, Object?>{'title': 'Home'},
        '/products/:id': <String, Object?>{'title': 'A product'},
        if (statusPage)
          '/500': <String, Object?>{
            'title': 'Something went wrong on our side',
            'text': <String>[
              'The problem has been recorded. Try again in a little while.',
            ],
          },
      },
    },
  ));
  return root;
}

Future<(Response, String)> get(String path, Directory root) async {
  final StringBuffer log = StringBuffer();
  final Response response = await IOOverrides.runZoned(
    () => handleSsrFallback(
      Request(
        method: 'GET',
        url: Uri.parse('http://acme.example$path'),
        headers: Headers(),
        bodyStream: const Stream<List<int>>.empty(),
      ),
      root.path,
      pageData: (DVPageRequest request) async {
        if (request.path.startsWith('/products/')) {
          throw StateError('database password rejected for user shop_rw');
        }
        return null;
      },
    ),
    stderr: () => _Capture(log),
  );
  return (response, log.toString());
}

Future<String> body(Response response) async => utf8.decode(<int>[
      for (final List<int> chunk in await response.body!.stream.toList())
        ...chunk,
    ]);

void main() {
  test('answers 500 with the shell, so the application still loads', () async {
    final (Response response, _) = await get('/products/42', site());
    expect(response.status, 500);
    expect(response.headers.get('content-type'), contains('text/html'));
    expect(await body(response), contains('<div id="app">'));
  });

  test("carries the 500 page's sentence for a reader with no JavaScript",
      () async {
    final (Response response, _) = await get('/products/42', site());
    final String html = await body(response);
    expect(html, contains('Something went wrong on our side'));
  });

  test('never puts the error in the body', () async {
    final (Response response, String log) = await get('/products/42', site());
    final String html = await body(response);
    expect(html, isNot(contains('database password')));
    expect(html, isNot(contains('StateError')));
    // The detail a developer needs is in the log instead.
    expect(log, contains('/products/42'));
    expect(log, contains('database password rejected'));
  });

  test('a build with no 500 page still answers 500 and hides the error',
      () async {
    final (Response response, _) =
        await get('/products/42', site(statusPage: false));
    expect(response.status, 500);
    expect(await body(response), isNot(contains('database password')));
  });

  test('a page whose data resolved is unaffected', () async {
    final (Response response, _) = await get('/', site());
    expect(response.status, 200);
  });
}

class _Capture implements Stdout {
  _Capture(this.buffer);

  final StringBuffer buffer;

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);

  @override
  void write(Object? object) => buffer.write(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
