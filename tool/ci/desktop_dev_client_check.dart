/// The dev client on a Windows or macOS desktop: launch a development build
/// with the pairing link `dartvel dev` prints as its launch flag, see an edit
/// made after it was built, then an edit saved while paired, in the same
/// process.
///
///     dart tool/ci/desktop_dev_client_check.dart windows|macos
///
/// The other desktops' half of linux_dev_client_check.dart, run by the "Dev
/// client" workflow on windows-latest and macos-latest. What is asserted:
/// - the link given on the command line pairs the app's native tunnel
///   (Schannel on Windows, Network.framework on macOS) over TLS pinned to the
///   key in the link (the dev server says the device paired);
/// - the page runs an edit made after the app was built once it pairs, which
///   only a hot restart onto the current sources can do;
/// - a second edit, saved while paired, runs the same way, by hot reload;
/// - the app's process is the same one across the reload.
///
/// A GUI application's own output does not reliably reach a parent
/// that pipes it, so an edit's marker is looked for both there and in what
/// `flutter attach` relays through `dartvel dev`.
///
/// Imports are `dart:` only, so this runs from a checkout with nothing
/// resolved.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

late final String _platform;
final String _sep = Platform.pathSeparator;
String get _example => 'examples${_sep}dartvel_example';
String get _binary => _platform == 'windows'
    ? '$_example\\build\\windows\\x64\\runner\\Debug\\dartvel_example.exe'
    : '$_example/build/macos/Build/Products/Debug/dartvel_example.app/Contents/MacOS/dartvel_example';
String get _diag => _platform == 'windows' ? r'C:\diag' : '/tmp/diag';
String get _page => [
  'examples',
  'dartvel_example',
  'lib',
  'pages',
  'index.page.dart',
].join(_sep);
const String _anchor = 'return DVBox.list([';

String _marker(String n) => 'DEVCLIENT-EDIT-$n';

String _withMarker(String source, String marker) {
  final int at = source.indexOf(_anchor);
  if (at < 0) {
    throw StateError('$_page no longer contains "$_anchor"; update the check.');
  }
  final String insert =
      "\n        (() { debugPrint('$marker'); "
      "return const DVText('$marker'); })(),";
  return source.replaceFirst(_anchor, '$_anchor$insert');
}

Future<bool> _waitFor(
  String what,
  Future<bool> Function() condition, {
  required Duration within,
}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (watch.elapsed < within) {
    if (await condition()) {
      stdout.writeln('== $what (${watch.elapsed.inSeconds}s)');
      return true;
    }
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  stdout.writeln('== timed out: $what');
  return false;
}

/// The application's process id.
Future<String?> _pid() async {
  if (_platform != 'windows') {
    final ProcessResult result = await Process.run('pgrep', <String>[
      '-f',
      'MacOS/dartvel_example',
    ]);
    final List<String> pids = '${result.stdout}'
        .split('\n')
        .map((String l) => l.trim())
        .where((String l) => l.isNotEmpty)
        .toList();
    return pids.isEmpty ? null : pids.first;
  }
  final ProcessResult result = await Process.run('tasklist', <String>[
    '/FI',
    'IMAGENAME eq dartvel_example.exe',
    '/FO',
    'CSV',
    '/NH',
  ]);
  for (final String line in '${result.stdout}'.split('\n')) {
    final List<String> cells = line.split(',');
    if (cells.length > 1 && cells[0].contains('dartvel_example')) {
      return cells[1].replaceAll('"', '').trim();
    }
  }
  return null;
}

void _collect(Process process, List<String> lines, IOSink log, String tag) {
  for (final Stream<List<int>> stream in <Stream<List<int>>>[
    process.stdout,
    process.stderr,
  ]) {
    stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((String line) {
          lines.add(line);
          log.writeln(line);
          stdout.writeln('[$tag] $line');
        });
  }
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 ||
      !<String>['windows', 'macos'].contains(arguments.single)) {
    stderr.writeln(
      'usage: dart tool/ci/desktop_dev_client_check.dart windows|macos',
    );
    exit(64);
  }
  _platform = arguments.single;
  Directory(_diag).createSync(recursive: true);
  final List<String> failures = <String>[];
  final File verdict = File('$_diag$_sep$_platform-devclient-verdict.txt');
  Process? dev;
  Process? app;
  final List<String> devLines = <String>[];
  final List<String> appLines = <String>[];
  final IOSink devLog = File(
    '$_diag$_sep$_platform-devclient-dev.log',
  ).openWrite();
  final IOSink appLog = File(
    '$_diag$_sep$_platform-devclient-app.log',
  ).openWrite();
  final File page = File(_page);
  final String original = page.readAsStringSync();
  bool ran(String marker) =>
      appLines.any((String l) => l.contains(marker)) ||
      devLines.any((String l) => l.contains(marker));

  try {
    if (!File(_binary).existsSync()) {
      throw StateError('$_binary was not built');
    }
    // An edit the app was not built with.
    page.writeAsStringSync(_withMarker(original, _marker('ONE')));

    dev = await Process.start(
      'dart',
      <String>['run', 'dartvel_cli:dartvel', 'dev', '--pairing-port', '8787'],
      workingDirectory: _example,
      runInShell: Platform.isWindows,
    );
    _collect(dev, devLines, devLog, 'dev');

    String? link;
    await _waitFor('the dev server printed a pairing link', () async {
      for (final String line in devLines) {
        final Match? m = RegExp(r'dartvel-dev://\S+').firstMatch(line);
        if (m != null) link = m.group(0);
      }
      return link != null;
    }, within: const Duration(minutes: 8));
    if (link == null) throw StateError('no pairing link was printed');
    if (!await _waitFor(
      'dartvel dev chose no local app',
      () async => devLines.any((String l) => l.contains('serving pairing')),
      within: const Duration(minutes: 3),
    )) {
      failures.add(
        'dartvel dev did not say it was serving pairing with no local app',
      );
    }

    // The launch flag: the link, as an argument.
    app = await Process.start(_binary, <String>[link!]);
    _collect(app, appLines, appLog, 'app');

    final bool paired = await _waitFor(
      'the app paired',
      () async => devLines.any((String l) => l.contains('paired ($_platform)')),
      within: const Duration(minutes: 3),
    );
    if (!paired) failures.add('the dev server never saw the app pair');

    final bool synced = await _waitFor(
      'the app was brought up to date',
      () async =>
          devLines.any((String l) => l.contains('up to date with the sources')),
      within: const Duration(minutes: 15),
    );
    if (!synced) failures.add('the app never reported up to date');

    final bool firstLogged = await _waitFor(
      'the first edit ran in the app',
      () async => ran(_marker('ONE')),
      within: const Duration(minutes: 2),
    );
    if (!firstLogged) {
      failures.add('the edit made before pairing never ran in the app');
    }

    final String? pidBefore = await _pid();
    final int reloadsBefore = devLines
        .where((String l) => l.contains('Reloaded'))
        .length;

    // A save while paired: a hot reload, not a relaunch.
    page.writeAsStringSync(_withMarker(original, _marker('TWO')));
    final bool reloaded = await _waitFor(
      'the dev server hot reloaded the app',
      () async =>
          devLines.where((String l) => l.contains('Reloaded')).length >
          reloadsBefore,
      within: const Duration(minutes: 5),
    );
    if (!reloaded) failures.add('no hot reload was reported after the save');

    final bool secondLogged = await _waitFor(
      'the second edit ran in the app',
      () async => ran(_marker('TWO')),
      within: const Duration(minutes: 2),
    );
    if (!secondLogged) failures.add('the saved edit never ran in the app');

    final String? pidAfter = await _pid();
    if (pidBefore == null || pidBefore != pidAfter) {
      failures.add(
        'the app process changed across the reload ($pidBefore -> $pidAfter)',
      );
    }
  } on Object catch (error, stack) {
    failures.add('the check stopped: $error');
    stderr.writeln(stack);
  } finally {
    page.writeAsStringSync(original);
    app?.kill();
    dev?.kill();
    if (_platform == 'windows') {
      await Process.run('taskkill', <String>[
        '/F',
        '/IM',
        'dartvel_example.exe',
      ]);
    } else {
      await Process.run('pkill', <String>['-f', 'MacOS/dartvel_example']);
    }
    await devLog.flush();
    await devLog.close();
    await appLog.flush();
    await appLog.close();
    verdict.writeAsStringSync(
      failures.isEmpty ? 'passed\n' : 'failed\n${failures.join('\n')}\n',
    );
    stdout.writeln(verdict.readAsStringSync());
  }
  exit(failures.isEmpty ? 0 : 1);
}
