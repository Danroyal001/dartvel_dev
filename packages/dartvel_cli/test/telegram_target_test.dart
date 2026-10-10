import 'dart:io';

import 'package:dartvel_cli/src/build/telegram.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:test/test.dart';

void main() {
  test('telegram uses the ordinary web compiler on every host', () {
    expect(buildPlatformArguments, contains('telegram'));
    expect(isPlatformAvailableOn('telegram', 'linux'), isTrue);
    expect(
      resolveFlutterBuildArguments(
        platform: 'telegram',
        buildMode: '--release',
      ).take(2),
      ['build', 'web'],
    );
  });
  test('shared shell loads SDK before bootstrap and is idempotent', () {
    final root = Directory.systemTemp.createTempSync('telegram-shell-');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/web').createSync();
    final file = File('${root.path}/web/index.html')
      ..writeAsStringSync(
        '<html><head></head><body><script src="flutter_bootstrap.js"></script></body></html>',
      );
    dvPrepareTelegramShell(root.path, enabled: true);
    final html = file.readAsStringSync();
    expect(
      html.indexOf('https://telegram.org/js/telegram-web-app.js'),
      lessThan(html.indexOf('flutter_bootstrap.js')),
    );
    dvPrepareTelegramShell(root.path, enabled: true);
    expect(file.readAsStringSync(), html);
    dvPrepareTelegramShell(root.path, enabled: false);
    expect(file.readAsStringSync(), isNot(contains('telegram-web-app.js')));
  });
}
