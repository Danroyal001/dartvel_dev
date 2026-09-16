/// The dev client on a real Android emulator: pair a development build with
/// `dartvel dev`, see the application's own page, edit it, and
/// see the edit without reinstalling.
///
/// Run by the "Dev client" workflow inside android-emulator-runner, which runs
/// each line of its script as a separate `sh -c`; everything is here, in one
/// command. The step is continue-on-error so the evidence uploads, so the
/// verdict is also written to a file a later step reads.
///
/// What is asserted, and how:
/// - the page shows an edit made after the APK was built -- in the flutter
///   log and in the accessibility tree -- once the device pairs, which only a
///   hot restart onto the current sources can do;
/// - a second edit, saved while paired, shows up the same way, by hot reload;
/// - the package was not reinstalled (its lastUpdateTime is unchanged) and the
///   process is the same one (its pid is unchanged across the reload).
///
/// Imports are `dart:` only, so this runs from a checkout with nothing
/// resolved.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _example = 'examples/dartvel_example';
const String _package = 'com.example.dartvel_example';
const String _diag = '/tmp/diag';
const String _page = '$_example/lib/pages/(tabs)/index.page.dart';
const String _anchor = 'return ShopScroll(children: <Widget>[';

String _marker(String n) => 'DEVCLIENT-EDIT-$n';

/// The page with a visible, logged marker as the first thing on it.
String dvWithMarker(String source, String marker) {
  final int at = source.indexOf(_anchor);
  if (at < 0) {
    throw StateError('$_page no longer contains "$_anchor"; update the check.');
  }
  final String insert =
      "\n        (() { debugPrint('$marker'); "
      "return const DVText('$marker'); })(),";
  return source.replaceFirst(_anchor, '$_anchor$insert');
}

/// [link] with its server pointed at [host], keeping the port.
///
/// The dev server advertises the runner's LAN address; the emulator reaches
/// the machine it runs on at 10.0.2.2. The key and token are unchanged, so the
/// pairing is exactly the one printed.
String dvLinkForHost(String link, String host) {
  final Uri uri = Uri.parse(link);
  final Uri server = Uri.parse(uri.queryParameters['server']!);
  return uri
      .replace(
        queryParameters: <String, String>{
          ...uri.queryParameters,
          'server': server.replace(host: host).toString(),
        },
      )
      .toString();
}

Future<ProcessResult> _adb(List<String> args) async {
  final ProcessResult result = await Process.run('adb', args);
  if (result.exitCode != 0) {
    throw StateError('adb ${args.join(' ')}: ${result.stderr}${result.stdout}');
  }
  return result;
}

Future<String> _adbText(List<String> args) async =>
    '${(await _adb(args)).stdout}';

Future<void> _screenshot(String name) async {
  final ProcessResult shot = await Process.run('adb', <String>[
    'exec-out',
    'screencap',
    '-p',
  ], stdoutEncoding: null);
  if (shot.exitCode == 0) {
    File('$_diag/$name.png').writeAsBytesSync(shot.stdout as List<int>);
    stdout.writeln('== screenshot $_diag/$name.png');
  }
}

Future<String> _uiDump() async {
  try {
    await _adb(<String>['shell', 'uiautomator', 'dump', '/sdcard/ui.xml']);
    return await _adbText(<String>['shell', 'cat', '/sdcard/ui.xml']);
  } on Object catch (error) {
    return 'uiautomator failed: $error';
  }
}

Future<String> _flutterLog() async =>
    _adbText(<String>['logcat', '-d', '-s', 'flutter:*', 'DartvelDevClient:*']);

Future<String?> _pid() async {
  final ProcessResult result = await Process.run('adb', <String>[
    'shell',
    'pidof',
    _package,
  ]);
  final String pid = '${result.stdout}'.trim();
  return pid.isEmpty ? null : pid;
}

Future<String> _lastUpdateTime() async {
  final String dump = await _adbText(<String>[
    'shell',
    'dumpsys',
    'package',
    _package,
  ]);
  return RegExp(r'lastUpdateTime=([^\n]+)').firstMatch(dump)?.group(1) ?? '';
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

Future<void> main() async {
  Directory(_diag).createSync(recursive: true);
  final List<String> failures = <String>[];
  final File verdict = File('$_diag/devclient-verdict.txt');
  Process? dev;
  final List<String> devLines = <String>[];
  final IOSink devLog = File('$_diag/devclient-dev.log').openWrite();

  try {
    await _adb(<String>['logcat', '-c']);
    await _adb(<String>[
      'install',
      '-r',
      '$_example/build/app/outputs/flutter-apk/app-debug.apk',
    ]);
    final String installedAt = await _lastUpdateTime();
    stdout.writeln('== installed, lastUpdateTime=$installedAt');

    await _adb(<String>[
      'shell',
      'monkey',
      '-p',
      _package,
      '-c',
      'android.intent.category.LAUNCHER',
      '1',
    ]);
    await Future<void>.delayed(const Duration(seconds: 25));
    await _screenshot('devclient-1-as-built');
    final String asBuilt = await _uiDump();
    File('$_diag/devclient-1-as-built.xml').writeAsStringSync(asBuilt);
    // Whether this emulator exposes Flutter's text to uiautomator at all. If
    // not, the flutter log is the evidence and the dump is not held against
    // the run.
    final bool uiReadable = asBuilt.contains('Oakline');
    stdout.writeln('== the accessibility tree is readable: $uiReadable');
    if (asBuilt.contains(_marker('ONE'))) {
      failures.add('the marker was on screen before any edit');
    }

    // An edit the APK was not built with.
    final File page = File(_page);
    final String original = page.readAsStringSync();
    page.writeAsStringSync(dvWithMarker(original, _marker('ONE')));

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
    // Pairing is always on, and on this runner flutter lists the emulator,
    // Linux and Chrome, so with no terminal to choose at dartvel dev must run
    // no local app: one on the emulator would install over the development
    // build being paired.
    // Device detection runs after the link is printed, so this is waited for.
    if (!await _waitFor(
      'dartvel dev chose no local app',
      () async => devLines.any((String l) => l.contains('serving pairing')),
      within: const Duration(minutes: 2),
    )) {
      failures.add(
        'dartvel dev did not say it was serving pairing with no '
        'local app; it may have started one on the emulator',
      );
    }

    final String emulatorLink = dvLinkForHost(link!, '10.0.2.2');
    stdout.writeln('== pairing with $emulatorLink');
    // Quoted for the device's shell: the link carries '&'.
    await _adb(<String>[
      'shell',
      "am start -a android.intent.action.VIEW -d '$emulatorLink'",
    ]);

    final bool synced = await _waitFor(
      'the device was brought up to date',
      () async =>
          devLines.any((String l) => l.contains('up to date with the sources')),
      within: const Duration(minutes: 12),
    );
    if (!synced) failures.add('the device never reported up to date');

    final bool firstLogged = await _waitFor(
      'the first edit ran on the device',
      () async => (await _flutterLog()).contains(_marker('ONE')),
      within: const Duration(minutes: 2),
    );
    if (!firstLogged) {
      failures.add('the edit made before pairing never ran on the device');
    }
    await Future<void>.delayed(const Duration(seconds: 5));
    await _screenshot('devclient-2-paired');
    final String paired = await _uiDump();
    File('$_diag/devclient-2-paired.xml').writeAsStringSync(paired);
    if (uiReadable && !paired.contains(_marker('ONE'))) {
      failures.add('the paired page does not show ${_marker('ONE')}');
    }

    final String? pidBefore = await _pid();
    final int reloadsBefore = devLines
        .where((String l) => l.contains('Reloaded'))
        .length;

    // A save while paired: a hot reload, not a reinstall.
    page.writeAsStringSync(dvWithMarker(original, _marker('TWO')));
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
      () async => (await _flutterLog()).contains(_marker('TWO')),
      within: const Duration(minutes: 2),
    );
    if (!secondLogged) failures.add('the saved edit never ran on the device');
    await Future<void>.delayed(const Duration(seconds: 5));
    await _screenshot('devclient-3-reloaded');
    final String after = await _uiDump();
    File('$_diag/devclient-3-reloaded.xml').writeAsStringSync(after);
    if (uiReadable && !after.contains(_marker('TWO'))) {
      failures.add('the reloaded page does not show ${_marker('TWO')}');
    }

    final String? pidAfter = await _pid();
    if (pidBefore == null || pidBefore != pidAfter) {
      failures.add(
        'the app process changed across the reload ($pidBefore -> $pidAfter)',
      );
    }
    final String updatedAt = await _lastUpdateTime();
    if (updatedAt != installedAt) {
      failures.add('the package was reinstalled ($installedAt -> $updatedAt)');
    }
    page.writeAsStringSync(original);
  } on Object catch (error, stack) {
    failures.add('the check stopped: $error');
    stderr.writeln(stack);
  } finally {
    try {
      File(
        '$_diag/devclient-logcat.log',
      ).writeAsStringSync(await _flutterLog());
    } on Object {
      // Diagnostics only.
    }
    dev?.kill();
    await devLog.flush();
    await devLog.close();
    verdict.writeAsStringSync(
      failures.isEmpty ? 'passed\n' : 'failed\n${failures.join('\n')}\n',
    );
    stdout.writeln(verdict.readAsStringSync());
  }
  exit(failures.isEmpty ? 0 : 1);
}
