// The dev server's half of the dev client: what `dartvel dev`
// serves, to whom, and whether what it serves is the current build.
//
// Over a real socket, because the failures worth catching are about what goes
// over the wire: a bundle handed to a device that never scanned the link, a
// manifest that is empty because nothing resolved the plugins yet, and the
// bundle from before the last edit.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/devclient/dev_client_server.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _plugins = '''
{"plugins":{"android":[
  {"name":"jni","native_build":true,"dev_dependency":false},
  {"name":"integration_probe","native_build":true,"dev_dependency":true},
  {"name":"pure_dart_plugin","native_build":false,"dev_dependency":false}
],"ios":[]}}
''';

void writeProject(Directory root, {bool plugins = true}) {
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dependencies:
  dartvel_flutter: ^0.4.0
''');
  File(p.join(root.path, 'pubspec.lock')).writeAsStringSync('''
packages:
  dartvel_flutter:
    dependency: "direct main"
    source: path
    version: "0.4.0"
''');
  if (plugins) {
    File(
      p.join(root.path, '.flutter-plugins-dependencies'),
    ).writeAsStringSync(_plugins);
  }
  writePage(root, 'about', 'About us');
}

void writePage(Directory root, String name, String title) {
  File(p.join(root.path, 'studio', 'pages', '$name.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode(<String, Object?>{
        'route': '/$name',
        'title': title,
        'root': <String, Object?>{'id': 'root', 'type': 'column'},
      }),
    );
}

void main() {
  late Directory root;
  late DVDevClientBundleServer server;
  late HttpClient http;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('dartvel_dev_client_');
    writeProject(root);
    server = await DVDevClientBundleServer.start(
      root: root.path,
      branch: 'feature/checkout',
      address: InternetAddress.loopbackIPv4,
      port: 0,
      advertisedHost: '127.0.0.1',
    );
    // Pinned to the link's key, as a device is.
    http = dvDevClientHttpClient(server.pairing);
  });

  tearDown(() async {
    http.close(force: true);
    await server.close();
    root.deleteSync(recursive: true);
  });

  Future<(int, String)> fetch({
    String? token,
    String target = 'android',
  }) async {
    final Uri uri = server.pairing.bundleUri(target);
    final HttpClientRequest request = await http.getUrl(uri);
    if (token != null) request.headers.set('authorization', 'Bearer $token');
    final HttpClientResponse response = await request.close();
    return (response.statusCode, await utf8.decodeStream(response));
  }

  test('the link a device scans parses and names this server', () {
    final DVDevClientPairing parsed = DVDevClientPairing.parse(
      server.pairing.link,
    );
    expect(parsed.branch, 'feature/checkout');
    expect(parsed.server.port, server.port);
    expect(parsed.token, server.pairing.token);
  });

  test('a paired device gets a sealed bundle it can open', () async {
    final (int status, String body) = await fetch(token: server.pairing.token);

    expect(status, 200, reason: body);
    final DVSignedBundle opened = DVSignedBundle.open(
      body,
      publicKey: server.pairing.publicKey,
      requireContentVersion: true,
    );
    expect(opened.channel, 'feature/checkout');
    expect(
      (opened.bundle['pages']! as List).single,
      containsPair('route', '/about'),
    );
    // Plugins compiled for Android, and the runtime version; not a dev
    // dependency, and not a plugin with nothing native in it.
    expect(opened.requires?.target, 'android');
    expect(opened.requires?.bindings, <String>[
      'dartvel_flutter@0.4.0',
      'plugin:jni',
    ]);
  });

  test(
    'pairing is served over TLS only: the link names https, and a '
    'plaintext request bearing the token is never answered with pages',
    () async {
      expect(server.pairing.server.scheme, 'https');

      // What a device sniffing the LAN would need the server to accept: the
      // token in the clear.
      final Socket plain = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final Uri uri = server.pairing.bundleUri('android');
      plain.write(
        'GET ${uri.path}?${uri.query} HTTP/1.1\r\n'
        'Host: 127.0.0.1:${server.port}\r\n'
        'Authorization: Bearer ${server.pairing.token}\r\n'
        'Connection: close\r\n\r\n',
      );
      final List<int> answer = <int>[];
      await plain
          .listen(answer.addAll, onError: (Object _) {})
          .asFuture<void>()
          .timeout(const Duration(seconds: 5), onTimeout: () {})
          .catchError((Object _) {});
      plain.destroy();
      final String text = latin1.decode(answer);
      expect(text, isNot(startsWith('HTTP/1.1')));
      expect(text, isNot(contains('About us')));
    },
  );

  group('the inspectors', () {
    void write(String relative, String content) {
      File(p.join(root.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    Future<(int, String)> inspect({String? token}) async {
      final HttpClientRequest request = await http.getUrl(
        server.pairing.graphUri(),
      );
      if (token != null) request.headers.set('authorization', 'Bearer $token');
      final HttpClientResponse response = await request.close();
      return (response.statusCode, await utf8.decodeStream(response));
    }

    test('a paired device reads the graph dartvel inspect answers, as the '
        'project is now', () async {
      write('lib/models/note.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Note {
  final String id;
  const _Note({required this.id});
}
''');
      final (int status, String body) = await inspect(
        token: server.pairing.token,
      );
      expect(status, 200, reason: body);
      final Map<String, Object?> graph =
          jsonDecode(body) as Map<String, Object?>;
      expect(
        (graph['models']! as List<Object?>).map(
          (Object? m) => (m! as Map<String, Object?>)['name'],
        ),
        contains('Note'),
      );

      // Read at request time: a model added after pairing is in the next
      // answer, as it is in the next `dartvel inspect`.
      write('lib/models/tag.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Tag {
  final String id;
  const _Tag({required this.id});
}
''');
      final (_, String again) = await inspect(token: server.pairing.token);
      expect(
        ((jsonDecode(again) as Map<String, Object?>)['models']!
                as List<Object?>)
            .map((Object? m) => (m! as Map<String, Object?>)['name']),
        containsAll(<String>['Note', 'Tag']),
      );
    });

    test('without the token there is no graph', () async {
      write('lib/models/note.dart', '@DVModel()\nclass _Note {}\n');
      final (int status, String body) = await inspect();
      expect(status, 401);
      expect(body, isNot(contains('Note')));
    });
  });

  test('no token gets nothing, and no hint of the content', () async {
    final (int status, String body) = await fetch();

    expect(status, 401);
    expect(body, isNot(contains('About us')));
  });

  test('a wrong token gets nothing', () async {
    final (int status, String body) = await fetch(
      token: DVDevClientPairing.newToken(),
    );

    expect(status, 401);
    expect(body, isNot(contains('About us')));
  });

  test('an edit is served as a new version with a higher sequence', () async {
    final (_, String first) = await fetch(token: server.pairing.token);
    writePage(root, 'about', 'About us, edited');
    final (_, String second) = await fetch(token: server.pairing.token);

    final DVSignedBundle a = DVSignedBundle.open(
      first,
      publicKey: server.pairing.publicKey,
    );
    final DVSignedBundle b = DVSignedBundle.open(
      second,
      publicKey: server.pairing.publicKey,
    );
    expect(b.bundle['version'], isNot(a.bundle['version']));
    expect(b.sequence, greaterThan(a.sequence!));
    expect(jsonEncode(b.bundle), contains('About us, edited'));
  });

  test('nothing changed is served as the same version and sequence', () async {
    final (_, String first) = await fetch(token: server.pairing.token);
    final (_, String second) = await fetch(token: server.pairing.token);

    final DVSignedBundle a = DVSignedBundle.open(
      first,
      publicKey: server.pairing.publicKey,
    );
    final DVSignedBundle b = DVSignedBundle.open(
      second,
      publicKey: server.pairing.publicKey,
    );
    expect(b.bundle['version'], a.bundle['version']);
    expect(b.sequence, a.sequence);
  });

  test('a plugin added to the project is in the next manifest', () async {
    // The case the manifest exists for: the device's shell predates it.
    File(p.join(root.path, '.flutter-plugins-dependencies')).writeAsStringSync(
      _plugins.replaceFirst(
        '"android":[',
        '"android":[{"name":"camera","native_build":true,"dev_dependency":false},',
      ),
    );

    final (_, String body) = await fetch(token: server.pairing.token);

    final DVSignedBundle opened = DVSignedBundle.open(
      body,
      publicKey: server.pairing.publicKey,
    );
    expect(opened.requires?.bindings, contains('plugin:camera'));
  });

  test('plugins that were never resolved refuse rather than serve an empty '
      'manifest', () async {
    // An empty manifest would load into any shell, including one missing
    // every plugin the project uses.
    File(p.join(root.path, '.flutter-plugins-dependencies')).deleteSync();

    final (int status, String body) = await fetch(token: server.pairing.token);

    expect(status, 503);
    expect(body, contains('pub get'));
  });

  test('a target it does not build shells for is refused', () async {
    final (int status, _) = await fetch(
      token: server.pairing.token,
      target: 'plan9',
    );
    expect(status, 400);
  });

  test('a page document with no route is refused, naming the file', () async {
    File(
      p.join(root.path, 'studio', 'pages', 'broken.json'),
    ).writeAsStringSync('{"title":"No route"}');

    final (int status, String body) = await fetch(token: server.pairing.token);

    expect(status, 500);
    expect(body, contains('broken.json'));
  });
}
