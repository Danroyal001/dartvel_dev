/// The Firefox profile an extension is loaded into, and what it said about it.
///
///     dart tool/ci/firefox_profile.dart prefs <profile> <addon-id> <uuid>
///     dart tool/ci/firefox_profile.dart addons <profile>/extensions.json
///
/// `prefs` writes the preferences that let an unsigned add-on load, pin its
/// moz-extension:// origin to a known uuid, and keep the first-run welcome
/// page from being what gets photographed instead of the extension.
///
/// `addons` prints what Firefox decided, so a page that never loads can be
/// told apart from an add-on that never installed.
library;

import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  exitCode = _run(arguments);
}

int _run(List<String> arguments) {
  switch (arguments.isEmpty ? '' : arguments.first) {
    case 'prefs':
      if (arguments.length != 4) return _usage();
      final String profile = arguments[1];
      final String addonId = arguments[2];
      final String uuid = arguments[3];
      // The uuid map is a JSON string holding JSON, which is how Firefox
      // stores it: encoded twice, deliberately.
      final String uuids =
          jsonEncode(jsonEncode(<String, String>{addonId: uuid}));
      const List<(String, String)> fixed = <(String, String)>[
        ('xpinstall.signatures.required', 'false'),
        ('extensions.autoDisableScopes', '0'),
        ('extensions.enabledScopes', '5'),
        ('browser.shell.checkDefaultBrowser', 'false'),
        ('toolkit.telemetry.enabled', 'false'),
        // Otherwise the first run opens a welcome page, which is what gets
        // photographed instead of the extension.
        ('browser.startup.homepage_override.mstone', '"ignore"'),
        ('browser.aboutwelcome.enabled', 'false'),
        ('datareporting.policy.firstRunURL', '""'),
        ('datareporting.policy.dataSubmissionEnabled', 'false'),
        ('trailhead.firstrun.didSeeAboutWelcome', 'true'),
        // The page's own console, on stdout. Without these a Flutter
        // start-up error is invisible: the DOM looks the same whether the
        // application threw or simply has not painted yet.
        ('devtools.console.stdout.content', 'true'),
        ('browser.dom.window.dump.enabled', 'true'),
      ];
      final StringBuffer out = StringBuffer()
        ..writeln('user_pref("extensions.webextensions.uuids", $uuids);');
      for (final (String name, String value) in fixed) {
        out.writeln('user_pref("$name", $value);');
      }
      File('$profile/prefs.js').writeAsStringSync(out.toString());
      return 0;
    case 'addons':
      if (arguments.length != 2) return _usage();
      final File file = File(arguments[1]);
      if (!file.existsSync()) return 0;
      final Object? decoded = jsonDecode(file.readAsStringSync());
      final Object? addons =
          decoded is Map<String, Object?> ? decoded['addons'] : null;
      if (addons is! List) return 0;
      for (final Object? addon in addons) {
        if (addon is! Map) continue;
        // Firefox's own bundled add-ons are app-global and say nothing about
        // the one being tested.
        if (addon['location'] == 'app-global') continue;
        stdout.writeln('addon ${addon['id']}: active=${addon['active']} '
            'type=${addon['type']}');
      }
      return 0;
    default:
      return _usage();
  }
}

int _usage() {
  stderr.writeln('usage: firefox_profile.dart prefs <profile> <id> <uuid>');
  stderr.writeln('       firefox_profile.dart addons <extensions.json>');
  return 2;
}
