// Deploys dartvel.dev: builds the site as a web-server binary, installs it
// beside the previous ones, swaps it in atomically, restarts the service and
// checks that it serves. A release that does not answer is swapped back out.
//
//   dart tool/deploy_site_server.dart               build, then deploy
//   dart tool/deploy_site_server.dart --skip-build  deploy sites/dartvel_site/build/server as it is
//   dart tool/deploy_site_server.dart --rollback    go back to the previous release
//
// Imports only dart: libraries, so it runs with nothing resolved.
//
// Layout under DARTVEL_SITE_ROOT:
//
//   releases/<stamp>-<sha>/server   every release installed, newest five kept
//   current -> releases/...         what the service runs
//   data/                           DARTVEL_DATA_DIR: the SQLite database with
//                                   the Studio account and grant; never touched
//
// The service is a systemd unit (DARTVEL_SITE_UNIT, Restart=always). The
// deploy restarts it by signalling its main process, which the unit's own
// user may do, so a deploy needs no sudo: systemd starts the process again,
// on the binary `current` now points at.
import 'dart:async';
import 'dart:io';

enum DeployMode { deploy, skipBuild, rollback }

DeployMode deployMode(List<String> args) => switch (args) {
      [] => DeployMode.deploy,
      ['--skip-build'] => DeployMode.skipBuild,
      ['--rollback'] => DeployMode.rollback,
      _ => throw ArgumentError.value(args.join(' '), 'args', 'unknown option'),
    };

/// The newest release other than [current], or null when there is none.
///
/// Release names start with a UTC stamp, so sorting the paths sorts them by
/// age.
String? previousRelease(List<String> releases, String? current) {
  final List<String> others =
      releases.where((String r) => r != current).toList()..sort();
  return others.isEmpty ? null : others.last;
}

/// The releases to delete so the newest [keep] stay, never [current].
List<String> releasesToPrune(
  List<String> releases,
  String? current, {
  int keep = 5,
}) {
  final List<String> sorted = List<String>.of(releases)..sort();
  if (sorted.length <= keep) return const <String>[];
  return sorted
      .take(sorted.length - keep)
      .where((String r) => r != current)
      .toList();
}

final String _root =
    Platform.environment['DARTVEL_SITE_ROOT'] ?? '/srv/dartvel.dev';
final String _port = Platform.environment['DARTVEL_SITE_PORT'] ?? '8740';
final String _unit = Platform.environment['DARTVEL_SITE_UNIT'] ?? 'dartvel-site';
final String _repo = File.fromUri(Platform.script).parent.parent.path;
final String _site = '$_repo/sites/dartvel_site';
final String _base = 'http://127.0.0.1:$_port';

void _say(String message) => stdout.writeln('deploy: $message');

Never _die(String message) {
  stderr.writeln('deploy: $message');
  exit(1);
}

Future<ProcessResult> _run(String executable, List<String> args,
        {String? workingDirectory}) =>
    Process.run(executable, args, workingDirectory: workingDirectory);

Future<void> _stream(String executable, List<String> args,
    {String? workingDirectory}) async {
  final Process process = await Process.start(executable, args,
      workingDirectory: workingDirectory, mode: ProcessStartMode.inheritStdio);
  final int code = await process.exitCode;
  if (code != 0) _die('$executable ${args.join(' ')} exited $code');
}

String? _resolved(String link) {
  final Link current = Link(link);
  if (!current.existsSync()) return null;
  return File(current.resolveSymbolicLinksSync()).absolute.path;
}

List<String> _releases() => Directory('$_root/releases')
    .listSync()
    .whereType<Directory>()
    .map((Directory d) => d.absolute.path)
    .toList();

/// Points `current` at [release]. A symlink replaced by rename is never
/// missing, even for an instant.
void _activate(String release) {
  final Link next = Link('$_root/current.next');
  if (next.existsSync()) next.deleteSync();
  next.createSync(release);
  next.renameSync('$_root/current');
}

Future<void> _restart() async {
  final ProcessResult shown =
      await _run('systemctl', <String>['show', '-p', 'MainPID', '--value', _unit]);
  final int pid = int.tryParse('${shown.stdout}'.trim()) ?? 0;
  if (pid != 0) {
    Process.killPid(pid, ProcessSignal.sigterm);
    // Wait for that process to go, so the check after is of the new one.
    for (int i = 0; i < 30; i++) {
      if (!Directory('/proc/$pid').existsSync()) break;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  } else {
    final ProcessResult started =
        await _run('systemctl', <String>['start', _unit]);
    if (started.exitCode != 0) {
      await _run('sudo', <String>['-n', 'systemctl', 'start', _unit]);
    }
  }
}

Future<bool> _healthy() async {
  final HttpClient client = HttpClient();
  try {
    for (int i = 0; i < 90; i++) {
      try {
        final HttpClientResponse response = await (await client
                .getUrl(Uri.parse('$_base/sitemap.xml')))
            .close();
        await response.drain<void>();
        if (response.statusCode == 200) break;
      } on IOException {
        // Not listening yet.
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  } finally {
    client.close(force: true);
  }
  // Every page in the sitemap rendered on the server with its title, meta
  // description and crawler text; Studio answering a stranger as an unknown
  // path; the image endpoint resizing.
  final Process check = await Process.start(Platform.resolvedExecutable,
      <String>['$_repo/tool/ci/server_pages_check.dart', _base],
      mode: ProcessStartMode.inheritStdio);
  return await check.exitCode == 0;
}

Future<void> main(List<String> args) async {
  final DeployMode mode;
  try {
    mode = deployMode(args);
  } on ArgumentError catch (error) {
    _die('${error.message}: ${error.invalidValue}');
  }
  if (!Directory('$_root/releases').existsSync()) {
    _die('$_root/releases does not exist; see sites/dartvel_site/README.md');
  }

  if (mode == DeployMode.rollback) {
    final String? previous =
        previousRelease(_releases(), _resolved('$_root/current'));
    if (previous == null) _die('no earlier release to go back to');
    _say('rolling back to $previous');
    _activate(previous);
    await _restart();
    if (!await _healthy()) _die('the previous release does not answer either');
    _say('rolled back');
    return;
  }

  if (mode == DeployMode.deploy) {
    _say('building the site as a web-server binary');
    await _stream('flutter', <String>['pub', 'get'], workingDirectory: _site);
    await _stream('dart',
        <String>['run', 'dartvel_cli:dartvel', 'build', 'web-server'],
        workingDirectory: _site);
  }
  final File built = File('$_site/build/server');
  if (!built.existsSync()) _die('no ${built.path}');

  final String sha = '${(await _run('git', <String>[
    '-C', _repo, 'rev-parse', '--short=8', 'HEAD',
  ])).stdout}'
      .trim();
  final DateTime now = DateTime.now().toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final String stamp = '${now.year}${two(now.month)}${two(now.day)}'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  final String release = '$_root/releases/$stamp-$sha';
  Directory(release).createSync(recursive: true);
  built.copySync('$release/server.tmp');
  await _run('chmod', <String>['755', '$release/server.tmp']);
  File('$release/server.tmp').renameSync('$release/server');

  final String? before = _resolved('$_root/current');
  _say('installing $release');
  _activate(release);
  await _restart();
  if (!await _healthy()) {
    _say('the new release failed its checks');
    final ProcessResult log = await _run(
        'journalctl', <String>['-u', _unit, '-n', '30', '--no-pager']);
    stdout.write(log.stdout);
    if (before != null) {
      _say('swapping back to $before');
      _activate(before);
      await _restart();
      if (!await _healthy()) _say('the previous release does not answer either');
    }
    exit(1);
  }

  // The newest five releases stay, and always the one running.
  for (final String old
      in releasesToPrune(_releases(), _resolved('$_root/current'))) {
    Directory(old).deleteSync(recursive: true);
  }
  _say('live: $release on $_base');
}
