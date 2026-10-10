// Run through ~/heavy.sh: dart tool/ci/telegram_build_check.dart
// Builds a fresh scaffold with this checkout's CLI, then inspects the bundle.
import 'dart:io';

Future<void> main(List<String> args) async {
  final repo = Directory.current.path;
  final root =
      args.isEmpty
            ? Directory.systemTemp.createTempSync('dv_telegram_')
            : Directory(args.single)
        ..createSync(recursive: true);
  Future<void> run(List<String> arguments, String cwd) async {
    final process = await Process.start(
      'dart',
      arguments,
      workingDirectory: cwd,
    );
    final out = stdout.addStream(process.stdout);
    final err = stderr.addStream(process.stderr);
    final code = await process.exitCode;
    await Future.wait([out, err]);
    if (code != 0) throw StateError('dart ${arguments.join(' ')} exited $code');
  }

  try {
    await run([
      'run',
      'dartvel_cli:dartvel',
      'create',
      root.path,
      '--project-name',
      'telegram_check',
      '--no-mobile',
      '--no-desktop',
    ], repo);
    await run([
      'run',
      'dartvel_cli:dartvel',
      'build',
      'telegram',
      '--no-auto-install',
    ], root.path);
    final html = File('${root.path}/build/web/index.html').readAsStringSync();
    final sdk = html.indexOf('https://telegram.org/js/telegram-web-app.js');
    if (sdk < 0 || sdk > html.indexOf('flutter_bootstrap.js')) {
      throw StateError('Built bundle must load the host SDK before Flutter');
    }
    if (!File('${root.path}/build/web/main.dart.js').existsSync()) {
      throw StateError('Missing compiled Flutter application');
    }
    stdout.writeln(
      'Telegram fresh-scaffold bundle verified: ${root.path}/build/web',
    );
  } finally {
    if (args.isEmpty) root.deleteSync(recursive: true);
  }
}
