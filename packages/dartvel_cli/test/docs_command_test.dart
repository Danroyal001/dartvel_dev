// `dartvel docs` and `dartvel docs --serve`.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:io';

import 'package:dartvel_cli/src/commands/docs_command.dart';
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
  test('builds the site into build/docs and reports drift', () async {
    final Directory root = _project();
    final List<String> lines = <String>[];
    final int code = await runDocs(root.path, out: lines.add);

    expect(code, 0, reason: 'drift is a warning unless asked to be fatal');
    final File index = File(p.join(root.path, 'build', 'docs', 'index.html'));
    expect(index.existsSync(), isTrue);
    expect(index.readAsStringSync(), contains('0001-users.html'));
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
    expect(File(p.join(root.path, 'site', 'models.html')).existsSync(), isTrue);
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
      final DVDocsServer server = await DVDocsServer.start(
        root: root.path,
        port: 0,
        out: (_) {},
      );
      addTearDown(server.close);

      final (int status, String index) = await _get(server.url);
      expect(status, 200);
      expect(index, contains('0001-users.html'));

      final (int missing, _) = await _get(server.url.resolve('nope.html'));
      expect(missing, 404);
      // Out of the site and into the project: a docs server must not serve
      // the application's source or its environment files.
      // Two levels: the site is build/docs, so one would land in build/, where
      // nothing exists and a 404 proves nothing about the guard.
      final (int escaped, String escapedBody) = await _get(
        Uri.parse('${server.url}..%2F..%2Fpubspec.yaml'),
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
        models = (await _get(server.url.resolve('models.html'))).$2;
        if (models.contains('id="model-Invoice"')) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(models, contains('id="model-Invoice"'));
      expect(models, contains('Sent at the end of the month.'));
    },
  );
}
