// Generated Code Determinism: identical inputs produce byte-identical output.
//
// Every generated file used to open with `// BUILD: <wall clock>#<millis>`,
// so every regeneration rewrote every file whether or not anything changed.
// A reviewer could not tell a real change from a rebuild, and `git status` was
// never clean after a build.
//
// These generate a real project with the real orchestrator -- pages, a model,
// a job, flags, a backend function -- and compare bytes. Nothing here reads
// the generated text for a particular shape; the property is the bytes.
@Timeout(Duration(minutes: 6))
library;

import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_cli/src/commands/version_command.dart';
import 'package:dartvel_cli/src/generators/generate_check.dart';
import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _pubspec = '''
name: determinism_probe
publish_to: none
environment:
  sdk: ^3.9.0
dartvel:
  prodBackendHost: https://example.com
''';

const String _indexPage = '''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => const DVText('Home');
''';

const String _postPage = '''
import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Post')
@pragma('vm:entry-point')
Widget _postPage(BuildContext context) => const DVText('Post');
''';

const String _model = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Account {
  final String id;
  final String email;
  final int seats;
  final DateTime createdAt;

  const _Account({
    required this.id,
    required this.email,
    required this.seats,
    required this.createdAt,
  });
}
''';

/// [queue] is the edit the one-input tests make: it reaches the generated
/// `static const String queue`, where an initialised field does not reach
/// the output at all.
String _job({String queue = 'mail'}) => '''
import 'package:dartvel_core/dartvel.dart';

@DVJob(queue: '$queue', maxAttempts: 5, backoffSeconds: 60)
class _SendWelcomeEmail {
  final String userId;

  const _SendWelcomeEmail({required this.userId});
}
''';

const String _flags = '''
import 'package:dartvel_core/dartvel.dart';

@DVFlags()
@pragma('vm:entry-point')
abstract class _Flags {
  @DVFlag(owner: 'payments', expires: '2099-12-01')
  static const bool newCheckout = false;
}
''';

const String _backendFunction = '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
@pragma('vm:entry-point')
Future<Map<String, Object?>> _ping() async => <String, Object?>{'ok': true};
''';

void _write(Directory root, String relative, String contents) {
  final File file = File(p.joinAll(<String>[root.path, ...relative.split('/')]));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

/// A project with one of each generation input, in a fresh temporary
/// directory.
Directory _project(String prefix) {
  final Directory root = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  _write(root, 'pubspec.yaml', _pubspec);
  _write(root, 'lib/pages/index.page.dart', _indexPage);
  _write(root, 'lib/pages/posts/[slug].page.dart', _postPage);
  _write(root, 'lib/models/account.dart', _model);
  _write(root, 'lib/jobs/welcome.dart', _job());
  _write(root, 'lib/flags/flags.dart', _flags);
  _write(root, 'lib/backend/functions/ping.get.dart', _backendFunction);
  return root;
}

/// Every file under [root], by forward-slash relative path.
Map<String, List<int>> _snapshot(Directory root) {
  final Map<String, List<int>> files = <String, List<int>>{};
  for (final FileSystemEntity entity
      in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final String relative =
        p.relative(entity.path, from: root.path).replaceAll(r'\', '/');
    files[relative] = entity.readAsBytesSync();
  }
  return files;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The paths added, removed or rewritten between two snapshots, sorted.
List<String> _changed(Map<String, List<int>> before, Map<String, List<int>> after) {
  final Set<String> paths = <String>{...before.keys, ...after.keys};
  return <String>[
    for (final String path in paths)
      if (!before.containsKey(path) ||
          !after.containsKey(path) ||
          !_sameBytes(before[path]!, after[path]!))
        path,
  ]..sort();
}

/// Generated output, as opposed to the inputs the fixture wrote.
bool _isGenerated(String path) =>
    path.startsWith('lib/dartvel_client/') || path.startsWith('.dart_tool/');

Future<void> _generate(Directory root) => routes.generate(root_: root.path);

/// The files a determinism claim is vacuous without.
const List<String> _expectedOutputs = <String>[
  'lib/dartvel_client/dartvel_client.dart',
  'lib/dartvel_client/router.g.dart',
  'lib/dartvel_client/models.g.dart',
  'lib/dartvel_client/jobs.g.dart',
  'lib/dartvel_client/flags.g.dart',
  'lib/dartvel_client/functions.g.dart',
  '.dart_tool/dartvel_backend.g.dart',
  '.dart_tool/dartvel_backend_routes.g.dart',
];

void main() {
  group('the same input', () {
    test('generated twice writes the same bytes', () async {
      final Directory project = _project('dartvel_det_twice_');

      await _generate(project);
      final Map<String, List<int>> first = _snapshot(project);
      expect(first.keys, containsAll(_expectedOutputs),
          reason: 'identical because nothing was generated proves nothing');

      await _generate(project);
      final Map<String, List<int>> second = _snapshot(project);

      expect(_changed(first, second), isEmpty,
          reason: 'a regeneration with nothing changed rewrote these files');
    });

    test('generated at another path writes the same bytes', () async {
      // The same project in two places is the same project. A path in the
      // output is a machine-specific value, and differs between a laptop and
      // CI the way it differs between these two directories.
      final Directory here = _project('dartvel_det_here_');
      final Directory there = _project('dartvel_det_there_elsewhere_');

      await _generate(here);
      await _generate(there);

      final Map<String, List<int>> a = _snapshot(here);
      expect(a.keys, containsAll(_expectedOutputs));
      expect(_changed(a, _snapshot(there)), isEmpty,
          reason: 'output depends on where the project is');
    });

    test('carries no stamp, no machine name and no absolute path', () async {
      final Directory project = _project('dartvel_det_values_');
      await _generate(project);

      final String hostname = Platform.localHostname;
      final RegExp wallClock =
          RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}');
      final List<String> offenders = <String>[];
      _snapshot(project).forEach((String path, List<int> bytes) {
        if (!_isGenerated(path)) return;
        final String text = String.fromCharCodes(bytes);
        if (text.contains('// BUILD:') || text.contains('Build ID:')) {
          offenders.add('$path: build stamp');
        }
        if (wallClock.hasMatch(text)) offenders.add('$path: timestamp');
        if (text.contains(project.path) ||
            text.contains(project.resolveSymbolicLinksSync())) {
          offenders.add('$path: absolute path');
        }
        if (hostname.length >= 6 && text.contains(hostname)) {
          offenders.add('$path: host name');
        }
      });

      expect(offenders, isEmpty);
    });

    test('records the generator version once', () async {
      // One file, so a generator upgrade is one deliberate line of diff
      // rather than a header change in every file.
      final Directory project = _project('dartvel_det_version_');
      await _generate(project);

      final String record = '// Generated by dartvel $dartvelCliVersion';
      final List<String> carrying = <String>[
        for (final MapEntry<String, List<int>> e in _snapshot(project).entries)
          if (_isGenerated(e.key) &&
              String.fromCharCodes(e.value).contains(record))
            e.key,
      ];

      expect(carrying, <String>['lib/dartvel_client/dartvel_client.dart']);
    });
  });

  test('changing one input rewrites only the files that depend on it',
      () async {
    final Directory project = _project('dartvel_det_one_input_');
    await _generate(project);
    final Map<String, List<int>> before = _snapshot(project);

    _write(project, 'lib/jobs/welcome.dart',
        _job(queue: 'email'));
    await _generate(project);
    final List<String> changed = _changed(before, _snapshot(project));

    expect(changed, contains('lib/dartvel_client/jobs.g.dart'),
        reason: 'the edit has to reach the output, or this proves nothing');
    expect(
      changed,
      everyElement(isIn(<String>[
        'lib/jobs/welcome.dart',
        'lib/dartvel_client/jobs.g.dart',
      ])),
      reason: 'a job edit rewrote files that do not depend on the job',
    );
  });

  group('dartvel generate --check', () {
    test('passes on output that matches its inputs', () async {
      final Directory project = _project('dartvel_check_fresh_');
      await _generate(project);

      final DVGenerateCheckResult result = await dvGenerateCheck(project.path);

      expect(result.stale, isEmpty);
      expect(result.unstable, isEmpty);
      expect(result.ok, isTrue);
    });

    test('names the stale paths and leaves the project untouched', () async {
      final Directory project = _project('dartvel_check_stale_');
      await _generate(project);
      _write(project, 'lib/jobs/welcome.dart',
          _job(queue: 'email'));
      final Map<String, List<int>> before = _snapshot(project);

      final DVGenerateCheckResult result = await dvGenerateCheck(project.path);

      expect(result.ok, isFalse);
      expect(result.stale, <String>['lib/dartvel_client/jobs.g.dart']);
      // A check that regenerates in place fixes what it was asked to report.
      expect(_changed(before, _snapshot(project)), isEmpty);
    });

    test('a hand edit to generated output is stale', () async {
      final Directory project = _project('dartvel_check_edited_');
      await _generate(project);
      final File router =
          File(p.join(project.path, 'lib', 'dartvel_client', 'router.g.dart'));
      router.writeAsStringSync('${router.readAsStringSync()}\n// edited\n');

      final DVGenerateCheckResult result = await dvGenerateCheck(project.path);

      expect(result.stale, <String>['lib/dartvel_client/router.g.dart']);
    });

    test('a generator that is not deterministic is DV-GEN-002', () async {
      // Generating twice and comparing is what keeps the contract honest.
      // This generator stamps the time, the way every generator here did.
      final Directory project = _project('dartvel_check_unstable_');
      int run = 0;
      Future<void> stamping(String root) async {
        run++;
        _write(Directory(root), 'lib/dartvel_client/stamp.g.dart',
            '// run $run\n');
        _write(Directory(root), 'lib/dartvel_client/steady.g.dart',
            '// steady\n');
      }

      final DVGenerateCheckResult result =
          await dvGenerateCheck(project.path, generator: stamping);

      expect(run, 2);
      expect(result.unstable, <String>['lib/dartvel_client/stamp.g.dart']);
      expect(result.ok, isFalse);
    });

    test('the command exits non-zero with the paths, and zero when fresh',
        () async {
      final Directory project = _project('dartvel_check_command_');
      await _generate(project);
      final String cli = await _cliEntrypoint();

      final ProcessResult fresh = await Process.run(
        Platform.resolvedExecutable,
        <String>[cli, 'generate', '--check'],
        workingDirectory: project.path,
      );
      expect(fresh.exitCode, 0, reason: '${fresh.stdout}${fresh.stderr}');

      _write(project, 'lib/jobs/welcome.dart',
          _job(queue: 'email'));
      final ProcessResult stale = await Process.run(
        Platform.resolvedExecutable,
        <String>[cli, 'generate', '--check'],
        workingDirectory: project.path,
      );
      final String output = '${stale.stdout}${stale.stderr}';
      expect(stale.exitCode, isNot(0), reason: output);
      expect(output, contains('DV-GEN-001'));
      expect(output, contains('lib/dartvel_client/jobs.g.dart'));
    });
  });
}

Future<String> _cliEntrypoint() async {
  final Uri? lib = await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/dartvel_cli.dart'));
  if (lib == null) throw StateError('dartvel_cli cannot resolve itself.');
  return p.join(p.dirname(p.dirname(lib.toFilePath())), 'bin', 'dartvel.dart');
}
