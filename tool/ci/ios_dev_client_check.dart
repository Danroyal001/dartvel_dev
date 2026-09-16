/// The dev client on an iOS simulator: pair a development build with
/// `dartvel dev` by opening its dartvel-dev:// link, see an edit made after
/// the app was built, then an edit saved while paired, in the same process.
///
/// The iOS half of android_dev_client_check.dart, run by the "Dev client"
/// workflow on a macOS runner. What is asserted, and how:
/// - the link reaches the app through the URL scheme the development
///   Info.plist declares (`xcrun simctl openurl`), and the native tunnel
///   pairs over TLS pinned to the key in the link;
/// - the page runs an edit made after the app was built -- in the app's log
///   -- once the device pairs, which only a hot restart onto the current
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
const String _app = '$_example/build/ios/iphonesimulator/Runner.app';
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

Future<String> _run(String executable, List<String> args) async {
  final ProcessResult result = await Process.run(executable, args);
  if (result.exitCode != 0) {
    throw StateError(
      '$executable ${args.join(' ')}: ${result.stderr}${result.stdout}',
    );
  }
  return '${result.stdout}';
}

Future<String> _simctl(List<String> args) =>
    _run('xcrun', <String>['simctl', ...args]);

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

/// An available iPhone simulator's udid, booted.
Future<String> _bootedIphone() async {
  final Map<String, Object?> list =
      jsonDecode(await _simctl(<String>['list', 'devices', 'available', '-j']))
          as Map<String, Object?>;
  final Map<String, Object?> runtimes =
      (list['devices']! as Map<Object?, Object?>).cast<String, Object?>();
  String? udid;
  for (final MapEntry<String, Object?> runtime in runtimes.entries) {
    if (!runtime.key.contains('iOS')) continue;
    for (final Object? device in runtime.value! as List<Object?>) {
      final Map<Object?, Object?> d = device! as Map<Object?, Object?>;
      if ('${d['name']}'.startsWith('iPhone')) {
        udid = '${d['udid']}';
        if (d['state'] == 'Booted') return udid;
      }
    }
  }
  if (udid == null) throw StateError('no available iPhone simulator');
  await Process.run('xcrun', <String>['simctl', 'boot', udid]);
  await _simctl(<String>['bootstatus', udid, '-b']);
  return udid;
}

Future<String?> _pid(String udid, String bundle) async {
  final ProcessResult result = await Process.run('xcrun', <String>[
    'simctl',
    'spawn',
    udid,
    'launchctl',
    'list',
  ]);
  for (final String line in '${result.stdout}'.split('\n')) {
    if (!line.contains('UIKitApplication:$bundle')) continue;
    final String pid = line.trim().split(RegExp(r'\s+')).first;
    return pid == '-' ? null : pid;
  }
  return null;
}

Future<void> main() async {
  Directory(_diag).createSync(recursive: true);
  final List<String> failures = <String>[];
  final File verdict = File('$_diag/ios-devclient-verdict.txt');
  Process? dev;
  Process? logs;
  final List<String> devLines = <String>[];
  final List<String> appLines = <String>[];
  final IOSink devLog = File('$_diag/ios-devclient-dev.log').openWrite();
  final IOSink appLog = File('$_diag/ios-devclient-app.log').openWrite();
  File? page;
  String? original;

  try {
    final String udid = await _bootedIphone();
    stdout.writeln('== simulator $udid');
    final String bundle = (await _run('/usr/libexec/PlistBuddy', <String>[
      '-c',
      'Print CFBundleIdentifier',
      '$_app/Info.plist',
    ])).trim();
    final String schemes = await _run('/usr/libexec/PlistBuddy', <String>[
      '-c',
      'Print CFBundleURLTypes',
      '$_app/Info.plist',
    ]);
    if (!schemes.contains('dartvel-dev')) {
      failures.add('the built app does not declare the dartvel-dev scheme');
    }

    // Everything the app logs: NSLog from the tunnel and Dart's prints.
    logs = await Process.start('xcrun', <String>[
      'simctl',
      'spawn',
      udid,
      'log',
      'stream',
      '--level',
      'debug',
      '--style',
      'compact',
      '--predicate',
      'process == "Runner"',
    ]);
    logs.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
      String line,
    ) {
      appLines.add(line);
      appLog.writeln(line);
    });

    await _simctl(<String>['install', udid, _app]);
    await _simctl(<String>['launch', udid, bundle]);
    await Future<void>.delayed(const Duration(seconds: 20));
    await Process.run('xcrun', <String>[
      'simctl',
      'io',
      udid,
      'screenshot',
      '$_diag/ios-devclient-1-as-built.png',
    ]);
    if (appLines.any((String l) => l.contains(_marker('ONE')))) {
      failures.add('the marker ran before any edit');
    }

    // An edit the app was not built with.
    page = File(_page);
    original = page.readAsStringSync();
    page.writeAsStringSync(_withMarker(original, _marker('ONE')));

    dev = await Process.start('dart', <String>[
      'run',
      'dartvel_cli:dartvel',
      'dev',
      '--pairing-port',
      '8787',
    ], workingDirectory: _example);
    for (final Stream<List<int>> stream in <Stream<List<int>>>[
      dev.stdout,
      dev.stderr,
    ]) {
      stream.transform(utf8.decoder).transform(const LineSplitter()).listen((
        String line,
      ) {
        devLines.add(line);
        devLog.writeln(line);
        stdout.writeln('[dev] $line');
      });
    }

    String? link;
    await _waitFor('the dev server printed a pairing link', () async {
      for (final String line in devLines) {
        final Match? m = RegExp(r'dartvel-dev://\S+').firstMatch(line);
        if (m != null) link = m.group(0);
      }
      return link != null;
    }, within: const Duration(minutes: 5));
    if (link == null) throw StateError('no pairing link was printed');
    if (!Uri.parse(
      Uri.parse(link!).queryParameters['server']!,
    ).isScheme('https')) {
      failures.add('the pairing link does not name an https server');
    }

    stdout.writeln('== opening $link');
    await _simctl(<String>['openurl', udid, link!]);

    final bool paired = await _waitFor(
      'the tunnel paired',
      () async => appLines.any((String l) => l.contains('paired with')),
      within: const Duration(minutes: 3),
    );
    if (!paired) failures.add('the app never reported paired');

    final bool synced = await _waitFor(
      'the device was brought up to date',
      () async =>
          devLines.any((String l) => l.contains('up to date with the sources')),
      within: const Duration(minutes: 12),
    );
    if (!synced) failures.add('the device never reported up to date');

    final bool firstLogged = await _waitFor(
      'the first edit ran on the device',
      () async => appLines.any((String l) => l.contains(_marker('ONE'))),
      within: const Duration(minutes: 2),
    );
    if (!firstLogged) {
      failures.add('the edit made before pairing never ran on the device');
    }
    await Future<void>.delayed(const Duration(seconds: 5));
    await Process.run('xcrun', <String>[
      'simctl',
      'io',
      udid,
      'screenshot',
      '$_diag/ios-devclient-2-paired.png',
    ]);

    final String? pidBefore = await _pid(udid, bundle);
    final int reloadsBefore = devLines
        .where((String l) => l.contains('Reloaded'))
        .length;

    // A save while paired: a hot reload, not a reinstall.
    page.writeAsStringSync(_withMarker(original, _marker('TWO')));
    final bool reloaded = await _waitFor(
      'the dev server hot reloaded the device',
      () async =>
          devLines.where((String l) => l.contains('Reloaded')).length >
          reloadsBefore,
      within: const Duration(minutes: 5),
    );
    if (!reloaded) failures.add('no hot reload was reported after the save');

    final bool secondLogged = await _waitFor(
      'the second edit ran on the device',
      () async => appLines.any((String l) => l.contains(_marker('TWO'))),
      within: const Duration(minutes: 2),
    );
    if (!secondLogged) failures.add('the saved edit never ran on the device');
    await Future<void>.delayed(const Duration(seconds: 5));
    await Process.run('xcrun', <String>[
      'simctl',
      'io',
      udid,
      'screenshot',
      '$_diag/ios-devclient-3-reloaded.png',
    ]);

    final String? pidAfter = await _pid(udid, bundle);
    if (pidBefore == null || pidBefore != pidAfter) {
      failures.add(
        'the app process changed across the reload ($pidBefore -> $pidAfter)',
      );
    }
  } on Object catch (error, stack) {
    failures.add('the check stopped: $error');
    stderr.writeln(stack);
  } finally {
    if (page != null && original != null) page.writeAsStringSync(original);
    dev?.kill();
    logs?.kill();
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
