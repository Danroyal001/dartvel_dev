import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late String cli;
  late Directory probe;
  final packages = p.absolute('.dart_tool/package_config.json');

  setUpAll(() async {
    probe = Directory.systemTemp.createTempSync('release_cli_probe_');
    final source = File(p.join(probe.path, 'main.dart'))
      ..writeAsStringSync("""
import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/dev_command.dart';
void main(List<String> args) async {
  await (CommandRunner<void>('dartvel', 'probe')..addCommand(DevCommand())).run(args);
}
""");
    cli = p.join(probe.path, 'probe.dill');
    final compiled = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'kernel',
      '--packages=$packages',
      source.path,
      '-o',
      cli,
    ]);
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}\n${compiled.stderr}',
    );
  });
  tearDownAll(() => probe.deleteSync(recursive: true));

  for (final serverRendered in [false, true]) {
    test(
      'release serves ${serverRendered ? 'rendered routes' : 'static output'} without generation',
      () async {
        final root = Directory.systemTemp.createTempSync('dev_release_');
        addTearDown(() => root.deleteSync(recursive: true));
        final web = Directory(p.join(root.path, 'build', 'web'))
          ..createSync(recursive: true);
        File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
          'name: release_fixture\ndartvel:\n  admin:\n    enabled: false\n',
        );
        File(p.join(web.path, 'index.html')).writeAsStringSync(
          '<!DOCTYPE html><html><head><!-- dartvel:seo --><title>Built output</title><!-- /dartvel:seo --></head><body>Release fixture</body></html>',
        );
        if (serverRendered) {
          File(p.join(web.path, 'dartvel_routes.json')).writeAsStringSync(
            jsonEncode({
              'routes': {
                '/article': {'title': 'Rendered article'},
              },
            }),
          );
        }
        final process = await Process.start(Platform.resolvedExecutable, [
          '--packages=$packages',
          cli,
          'dev',
          '--release',
          '--host',
          '127.0.0.1',
          '--port',
          '0',
        ], workingDirectory: root.path);
        addTearDown(() async {
          process.kill(.sigkill);
          await process.exitCode;
        });
        final output = StringBuffer();
        final ready = Completer<int>();
        process.stderr.transform(utf8.decoder).listen(output.write);
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              output.writeln(line);
              final match = RegExp(r'Server started successfully.*:(\d+)')
                  .firstMatch(line);
              if (match != null && !ready.isCompleted) {
                ready.complete(int.parse(match[1]!));
              }
            });
        unawaited(
          process.exitCode.then((code) {
            if (!ready.isCompleted) {
              ready.completeError(StateError('server exited $code: $output'));
            }
          }),
        );
        final port = await ready.future.timeout(
          const Duration(seconds: 25),
          onTimeout: () => throw StateError('$output'),
        );
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final response = await (await client.getUrl(
          Uri.parse(
            'http://127.0.0.1:$port/${serverRendered ? 'article' : ''}',
          ),
        )).close();
        final html = await utf8.decoder.bind(response).join();
        expect(response.statusCode, 200);
        expect(
          html,
          contains(serverRendered ? 'Rendered article' : 'Built output'),
        );
        expect(Directory(p.join(root.path, 'lib')).existsSync(), isFalse);
        expect(output.toString(), isNot(contains('pairing')));
        process.kill(.sigint);
        expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
      },
    );
  }
}
