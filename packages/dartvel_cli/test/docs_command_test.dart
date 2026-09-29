// `dartvel docs` and `dartvel docs --serve`.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:io';

import 'package:dartvel_cli/src/commands/docs_command.dart';
import 'package:dartvel_cli/src/docs/docs_document.dart';
import 'package:dartvel_cli/src/docs/docs_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const Map<String, String> _files = <String, String>{
  'pubspec.yaml': 'name: docs_cmd_probe\npublish_to: none\n',
  'lib/models/user.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _User {
  final String email;

  const _User({required this.email});
}
''',
  'docs/decisions/0001-users.md': '''
# 1. Users sign in by email

`model:User` is keyed by `field:User.email`, and `model:Account` is gone.
''',
};

Directory _project() {
  final Directory root = Directory.systemTemp.createTempSync('dv_docs_cmd_');
  addTearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  _files.forEach((String relative, String contents) {
    final File file = File(
      p.joinAll(<String>[root.path, ...relative.split('/')]),
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  });
  return root;
}

Future<(int, String)> _get(Uri url) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(url);
    final HttpClientResponse response = await request.close();
    final String body = await response
        .transform(const SystemEncoding().decoder)
        .join();
    return (response.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('builds the document into build/docs and reports drift', () async {
    final Directory root = _project();
    final List<String> lines = <String>[];
    final int code = await runDocs(root.path, out: lines.add);

    expect(code, 0, reason: 'drift is a warning unless asked to be fatal');
    // The document, and the graph beside it. Not pages: the site is an
    // application, and what it draws is written next to it.
    final File payload = File(
      p.join(root.path, 'build', 'docs', dvDocsPayloadFile),
    );
    expect(payload.existsSync(), isTrue);
    expect(payload.readAsStringSync(), contains('decision:0001-users'));
    expect(
      File(p.join(root.path, 'build', 'docs', dvDocsGraphFile)).existsSync(),
      isTrue,
    );
    expect(lines.join('\n'), contains('DV-DOCS-001'));
    expect(lines.join('\n'), contains('docs/decisions/0001-users.md:3'));
    expect(lines.join('\n'), contains('model:Account'));
  });

  test(
    '--fatal-warnings fails on drift, and passes once it is fixed',
    () async {
      final Directory root = _project();
      expect(
        await runDocs(root.path, fatalWarnings: true, out: (_) {}),
        isNot(0),
      );
      File(
        p.join(root.path, 'docs', 'decisions', '0001-users.md'),
      ).writeAsStringSync('# 1. Users sign in by email\n\n`model:User`.\n');
      expect(await runDocs(root.path, fatalWarnings: true, out: (_) {}), 0);
    },
  );

  test('--output is relative to the project', () async {
    final Directory root = _project();
    await runDocs(root.path, output: 'site', out: (_) {});
    expect(File(p.join(root.path, 'site', dvDocsPayloadFile)).existsSync(), isTrue);
  });

  test('refuses to write over a directory it did not build', () async {
    final Directory root = _project();
    final List<String> lines = <String>[];
    expect(await runDocs(root.path, output: 'lib', out: lines.add), isNot(0));
    expect(
      File(p.join(root.path, 'lib', 'models', 'user.dart')).existsSync(),
      isTrue,
    );
    expect(lines.join('\n'), contains('not written by dartvel docs'));
  });

  test(
    '--serve serves the site and rebuilds it when the source changes',
    () async {
      final Directory root = _project();
      final List<List<String>> runs = <List<String>>[];

      Future<ProcessResult> compiles(String executable, List<String> arguments,
          {String? workingDirectory}) async {
        runs.add(<String>[executable, ...arguments]);
        final String out = arguments[arguments.indexOf('-o') + 1];
        File(p.join(out, 'main.dart.js'))
          ..createSync(recursive: true)
          ..writeAsStringSync('// docs app');
        File(p.join(out, 'flutter_bootstrap.js')).writeAsStringSync('// boot');
        File(p.join(out, 'canvaskit', 'canvaskit.wasm'))
          ..createSync(recursive: true)
          ..writeAsBytesSync(<int>[0, 97, 115, 109]);
        File(p.join(out, 'index.html'))
            .writeAsStringSync('<html><title>docs</title></html>');
        // Do NOT overwrite docs.json - it was already written by dvDocsBuildInto
        return ProcessResult(0, 0, '', '');
      }

      final DVDocsServer server = await DVDocsServer.start(
        root: root.path,
        port: 0,
        out: (_) {},
        run: compiles,
      );
      addTearDown(server.close);

      final (int status, String payload) = await _get(
        server.url.resolve(dvDocsPayloadFile),
      );
      expect(status, 200);
      expect(payload, contains('decision:0001-users'));

      // For a Flutter SPA, paths that don't exist as files serve index.html
      // so the client-side router can handle them.
      final (int missing, String missingBody) = await _get(server.url.resolve('nope.json'));
      expect(missing, 200);
      expect(missingBody, contains('<html lang="en">'));
      // Out of the site and into the project: a docs server must not serve
      // the application's source or its environment files.
      // Path traversal attempts are blocked.
      final (int escaped, String escapedBody) = await _get(
        server.url.resolve('..%2F..%2Fpubspec.yaml'),
      );
      expect(escaped, 404);
      expect(escapedBody, isNot(contains('docs_cmd_probe')));

      File(
        p.join(root.path, 'lib', 'models', 'invoice.dart'),
      ).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

/// Sent at the end of the month.
@DVModel()
class _Invoice {
  final int total;

  const _Invoice({required this.total});
}
''');
      final Stopwatch waited = Stopwatch()..start();
      String models = '';
      while (waited.elapsed < const Duration(seconds: 30)) {
        models = (await _get(server.url.resolve(dvDocsPayloadFile))).$2;
        if (models.contains('"Invoice"')) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(models, contains('"Invoice"'));
      expect(models, contains('Sent at the end of the month.'));
    },
  );
}
