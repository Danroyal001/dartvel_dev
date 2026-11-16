// docs:start platforms-web-config
// The same setting in a Dart config class (`dartvel: lib/services/...` in
// pubspec.yaml). DVWebFile.analytics is generated from web/analytics.html, so
// renaming or deleting the file is a compile error.
import 'package:dartvel_core/config.dart';

import '../dartvel_client/web_files.g.dart';

class const SiteConfig() extends DartvelConfig {
  @override
  DVPlatformSettings get platforms => const DVPlatformSettings(
        web: DVWebSettings(
          document: DVWebDocumentSlots(
            head: <DVHtmlSnippet>[
              DVHtmlSnippet.html('<meta name="google-site-verification" content="your-code">'),
              DVHtmlSnippet.file(DVWebFile.analytics),
            ],
            bodyEnd: <DVHtmlSnippet>[
              DVHtmlSnippet.html('<script src="https://cdn.example.com/chat.js" async></script>'),
            ],
          ),
        ),
      );
}
// docs:end
