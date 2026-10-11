import 'package:flutter/material.dart';

import '../../components/site.dart';
import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel build targets: every platform and its status',
  description: 'Build one Dartvel app for phones, desktops, the web and '
      'TVs, with the verified status of every target, and the paid targets '
      'every Dartvel Cloud plan includes.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsBuildingPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsbuilding,
      lead: <String>[
        'Build one app for phones, desktops, the web and TVs.',
        'Each target below shows what has been verified by running the build.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'command',
          title: 'Build with one command',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel build web',
              'dartvel build android',
              'dartvel build    # every target this machine can build',
              'dartvel build linux --profile development',
            ]),
            Bullets(<String>[
              'Code generation runs first, so there is no separate step.',
              '--profile takes development, profile or release. release is the '
                  'default.',
              'A target this host cannot build is skipped with the reason.',
            ]),
          ],
        ),
        DocsSection(
          id: 'tools',
          title: 'Check tools before you build',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel doctor',
              'dartvel doctor --target tizen',
              'dartvel build webos --auto-install',
            ]),
            Bullets(<String>[
              'The build checks the host, then the tools, before it generates '
                  'anything.',
              'Tools Dartvel can fetch unattended install under '
                  '~/.dartvel/toolchains. It asks first, and installs without '
                  'asking in CI.',
              'Xcode, Visual Studio, the Android SDK and Tizen Studio are never '
                  'installed for you.',
            ]),
            DocsText('Inside a project, doctor also checks the directories you '
                'configured as pagesDir, backendDir and modelsDir. A project '
                'that does not use one gets a [-] line, which is information '
                'and needs no fix. [!] is kept for something you have to fix.'),
            DocsShell(<String>[
              '[+] lib/pages exists',
              '[-] lib/backend/functions not present (no backend functions)',
              '[-] lib/models not present (no models)',
            ]),
          ],
        ),
        DocsSection(
          id: 'targets',
          title: 'Every target and its status',
          children: <Widget>[
            DocsTable(columns: <String>[
              'Target',
              'Needs',
              'Status',
            ], rows: <List<String>>[
              <String>['web', 'Any host', 'Builds, and runs in headless Chrome'],
              <String>['android', 'The Android SDK', 'Builds an APK'],
              <String>['fireos', 'The Android SDK', 'Builds the Android APK'],
              <String>['ios', 'macOS with Xcode', 'Builds, verified on a macOS '
                  'runner'],
              <String>['macos', 'macOS', 'Builds a universal binary'],
              <String>['windows', 'Windows', 'Builds, verified on a Windows '
                  'runner'],
              <String>['linux', 'Linux', 'Builds and runs'],
              <String>['tvos', 'macOS with Xcode', 'Builds and runs on the '
                  'simulator. Signed device builds are not verified'],
              <String>['tizen (alias tpk)', 'Tizen Studio', 'Builds a signed '
                  'TPK. CI can only skip it'],
              <String>['sony-elinux', 'Linux', 'Builds and runs in release on '
                  'a virtual device'],
              <String>['webos', 'The webOS toolchain', '`dartvel build webos` '
                  'skips: LG\'s CLI cannot resolve a Dartvel project. A package '
                  'assembled in CI runs in a Wayland window under ARM '
                  'emulation. Not run on a TV'],
              <String>['web-server', 'Any host', 'See Servers and deploying'],
            ]),
            DocsText('The evidence for every row, with CI run links, is in '
                'build-targets.md.'),
            ExternalLink('Read build-targets.md', kBuildTargetsUrl),
          ],
        ),
        DocsSection(
          id: 'android-release',
          title: 'Android release builds',
          children: <Widget>[
            DocsText('A release build of android or fireos is signed '
                'with your own key. Without one the build stops before it '
                'starts and says how to set one up. It is never signed with '
                'the debug key.'),
            DocsYaml('yaml-android-release'),
            DocsShell(<String>[
              'keytool -genkeypair -v -keystore upload.jks -keyalg RSA '
                  '-keysize 4096 -validity 10000 -alias upload',
              'dartvel build android',
            ]),
            Bullets(<String>[
              'The properties file holds storeFile, storePassword, keyAlias '
                  'and keyPassword. storeFile is relative to the file.',
              'In CI, set DARTVEL_ANDROID_KEYSTORE, '
                  'DARTVEL_ANDROID_KEYSTORE_PASSWORD and '
                  'DARTVEL_ANDROID_KEY_ALIAS instead.',
              'The app may use the network. Set internet: false if it never '
                  'does.',
              'Backup is off, including copying to a new phone. With '
                  'allowBackup: true, the app\'s databases, its sign-in and '
                  'its offline data still stay on the device.',
              'Plain HTTP is refused except to the hosts you list. Debug '
                  'builds can also reach your computer from the emulator.',
              'Release builds keep the Java Dartvel calls by name, so '
                  'shrinking the app does not break the camera or payments.',
            ]),
          ],
        ),
        DocsSection(
          id: 'embedded',
          title: 'TVs and embedded devices use vendor embedders',
          children: <Widget>[
            Bullets(<String>[
              'tizen, sony-elinux, webos and tvos build through the '
                  'platform\'s own Flutter embedder.',
              'Dartvel keeps a pinned fork of each, which it can install for '
                  'you.',
              '--arch picks arm, arm64 or x64 for embedded builds. It '
                  'defaults to arm64, and to this '
                  'machine\'s own for sony-elinux.',
            ]),
            DocsNote('sony-elinux-iso and sony-elinux-img',
                'These names are accepted. Today they build the same bundle as '
                'sony-elinux, with no disk image.'),
            UpstreamCredits(
              ids: <String>['tizen', 'elinux', 'webos', 'tvos'],
              lead: 'Thanks to the embedders these targets are built on:',
              link: false,
            ),
          ],
        ),
        DocsSection(
          id: 'paid',
          title: 'Paid targets',
          children: <Widget>[
            DocsText('Some targets are not officially supported by Flutter. '
                'They come with every Dartvel Cloud plan instead of the free '
                'install: Apple Vision Pro, Meta Quest, Chrome and Firefox '
                'extensions, VS Code extensions, Telegram Mini Apps, apps that '
                'run in a terminal, and Fuchsia.'),
            DocsTable(columns: <String>[
              'Target',
              'What it builds',
            ], rows: <List<String>>[
              <String>['visionos', 'The iPad app Apple Vision Pro runs'],
              <String>['horizon', 'A Meta Quest panel app'],
              <String>['chrome-extension, firefox-extension',
                  'A browser extension'],
              <String>['vscode', 'A VS Code extension'],
              <String>['telegram', 'A Telegram Mini App'],
              <String>['linux-cli, macos-cli, windows-cli, fuchsia-cli',
                  'The app in a terminal, with no window'],
              <String>['fuchsia', 'A Fuchsia package'],
            ]),
            DocsShell(<String>[
              'dartvel build visionos --cloud   # build it on Dartvel Cloud',
              'dartvel targets add pro          # or add the package and build here',
              'dartvel targets                  # what this install can build',
            ]),
            Bullets(<String>[
              'Without a plan, dartvel build visionos says which plan '
                  'includes it and stops. Nothing is built or sent.',
              'The package adds build steps only. Nothing from it, and no '
                  'licence key, ends up in your app.',
              'Dartvel 0.11.5 and earlier built these targets in the open, '
                  'and those releases stay MIT licensed.',
            ]),
            DocsNote('Your own targets',
                'The way a paid target plugs in is public. Any package can add '
                'a build target the same way: see the CLI README.'),
          ],
        ),
        DocsSection(
          id: 'upstream',
          title: 'Upstream embedders and credits',
          children: <Widget>[
            DocsText('Every TV, embedded, extension and terminal target runs on '
                'an embedder somebody else wrote. Dartvel keeps a fork of each '
                'so it can pin, patch and track it against the Flutter version '
                'Dartvel ships. Each fork keeps upstream\'s licence and docs '
                'untouched below a banner that says what changed.'),
            UpstreamTable(),
            DocsText('Thank you to the maintainers of these projects at '
                'Samsung, Sony, LG, the Fuchsia team, FlutterTV, Bitwild, and '
                'to SlowGen and Jia Hao. Dartvel\'s TV, embedded and terminal '
                'targets exist because they did the hard part first.'),
            DocsSubheading('Also built on'),
            UpstreamCredit('flutter', lead: 'Every target is'),
            UpstreamCredit('go_router', lead: 'The generated router is built on'),
            UpstreamCredit('shorebird', lead: 'DV.Updates runs on the'),
            UpstreamCredit('axum', lead: 'The Rust server is built on'),
            UpstreamCredit('tokio', lead: 'It runs on'),
          ],
        ),
      ],
    );
