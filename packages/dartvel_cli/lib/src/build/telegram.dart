import 'dart:io';

import 'package:path/path.dart' as p;

/// SDK in the existing web shell, shared by static and server rendering.
/// A managed block can be removed when switching back to a plain web build.
void dvPrepareTelegramShell(String root, {required bool enabled}) {
  final file = File(p.join(root, 'web', 'index.html'));
  if (!file.existsSync()) return;
  final before = file.readAsStringSync();
  var after = before.replaceAll(
    RegExp(
      r'\n?<!-- dartvel:telegram -->[\s\S]*?<!-- /dartvel:telegram -->\n?',
    ),
    '',
  );
  if (enabled) {
    after = after.replaceFirst('</head>', '''<!-- dartvel:telegram -->
<script src="https://telegram.org/js/telegram-web-app.js"></script>
<!-- /dartvel:telegram -->
</head>''');
  }
  if (after != before) file.writeAsStringSync(after);
}
