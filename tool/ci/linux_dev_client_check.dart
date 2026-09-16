/// The dev client on Linux: launch a development build with the pairing link
/// `dartvel dev` prints as its launch flag, see an edit made after it was
/// built, then an edit saved while paired, in the same process.
///
/// The desktop half of android_dev_client_check.dart, run by the "Dev client"
/// workflow under a virtual display. What is asserted, and how:
/// - the link given on the command line pairs the app's C++ tunnel over TLS
///   pinned to the key in the link (the app says "paired with");
/// - the page runs an edit made after the app was built -- in the app's own
///   output -- once it pairs, which only a hot restart onto the current
///   sources can do;
/// - a second edit, saved while paired, runs the same way, by hot reload;
/// - the app's process is the same one across the reload.
///
/// Imports are `dart:` only, so this runs from a checkout with nothing
/// resolved.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _example = 'examples/dartvel_example';
const String _binary = '$_example/build/linux/x64/debug/bundle/dartvel_example';
const String _diag = '/tmp/diag';
const String _page = '$_example/lib/pages/index.page.dart';
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

/// The pid of the application process, not the display wrapper around it.
Future<String?> _pid() async {
  final ProcessResult result = await Process.run('pgrep', <String>[
    '-f',
    '^[^ ]*bundle/dartvel_example ',
  ]);
  final List<String> pids = '${result.stdout}'
      .split('\n')
      .map((String l) => l.trim())
      .where((String l) => l.isNotEmpty)
      .toList();
  return pids.isEmpty ? null : pids.first;
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

Future<void> main() async {
  Directory(_diag).createSync(recursive: true);
  final List<String> failures = <String>[];
  final File verdict = File('$_diag/linux-devclient-verdict.txt');
  Process? dev;
  Process? app;
  final List<String> devLines = <String>[];
  final List<String> appLines = <String>[];
  final IOSink devLog = File('$_diag/linux-devclient-dev.log').openWrite();
  final IOSink appLog = File('$_diag/linux-devclient-app.log').openWrite();
  final File page = File(_page);
  final String original = page.readAsStringSync();

  try {
    if (!File(_binary).existsSync()) {
      throw StateError('$_binary was not built');
    }
    // An edit the app was not built with.
    page.writeAsStringSync(_withMarker(original, _marker('ONE')));

    dev = await Process.start('dart', <String>[
      'run',
      'dartvel_cli:dartvel',
      'dev',
      '--pairing-port',
      '8787',
    ], workingDirectory: _example);
    _collect(dev, devLines, devLog, 'dev');

    String? link;
    await _waitFor('the dev server printed a pairing link', () async {
      for (final String line in devLines) {
        final Match? m = RegExp(r'dartvel-dev://\S+').firstMatch(line);
        if (m != null) link = m.group(0);
      }
      return link != null;
    }, within: const Duration(minutes: 5));
    if (link == null) throw StateError('no pairing link was printed');
    if (!await _waitFor(
      'dartvel dev chose no local app',
      () async => devLines.any((String l) => l.contains('serving pairing')),
      within: const Duration(minutes: 2),
    )) {
      failures.add(
        'dartvel dev did not say it was serving pairing with no local app',
      );
    }

    // The launch flag: the link, as an argument.
    app = await Process.start('xvfb-run', <String>['-a', _binary, link!]);
    _collect(app, appLines, appLog, 'app');

    final bool paired = await _waitFor(
      'the app paired',
      () async => appLines.any((String l) => l.contains('paired with')),
      within: const Duration(minutes: 3),
    );
    if (!paired) failures.add('the app never reported paired');

    final bool synced = await _waitFor(
      'the app was brought up to date',
      () async =>
          devLines.any((String l) => l.contains('up to date with the sources')),
      within: const Duration(minutes: 12),
    );
    if (!synced) failures.add('the app never reported up to date');

    final bool firstLogged = await _waitFor(
      'the first edit ran in the app',
      () async => appLines.any((String l) => l.contains(_marker('ONE'))),
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
      () async => appLines.any((String l) => l.contains(_marker('TWO'))),
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
    dev?.kill();
    app?.kill();
    await Process.run('pkill', <String>['-f', 'bundle/dartvel_example']);
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
