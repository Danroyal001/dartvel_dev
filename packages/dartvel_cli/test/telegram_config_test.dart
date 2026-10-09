import 'dart:io';

import 'package:dartvel_cli/src/config/dartvel_config.dart';
import 'package:test/test.dart';

void main() {
  test(
    'server secrets cannot be declared in public Telegram configuration',
    () async {
      final root = Directory.systemTemp.createTempSync('telegram-config-');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/pubspec.yaml').writeAsStringSync(
        'name: app\ndartvel:\n  telegram:\n    botToken: secret\n',
      );
      await expectLater(DartvelConfig.load(root), throwsFormatException);
    },
  );
}
