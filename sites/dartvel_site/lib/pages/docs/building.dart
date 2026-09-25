import 'package:flutter/material.dart';

import '../../components/site.dart';
import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel build targets: every platform and its status',
  description: 'Build one Dartvel app for phones, desktops, the web, TVs, '
      'browser extensions and the terminal, with the verified status '
      'of every target.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsBuildingPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsbuilding,
      lead: <String>[
        'Build one app for phones, desktops, the web, TVs, browser extensions '
            'and the terminal.',
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
              <String>['webos', 'The webOS toolchain', 'Runs in a Wayland '
                  'window under ARM emulation. Not run on a TV'],
              <String>['fuchsia', 'Linux', 'Blocked: the embedder\'s Flutter '
                  'is too old to resolve dependencies'],
              <String>['vscode', 'npm', 'Builds a VS Code extension'],
              <String>['chrome-extension', 'Any host', 'Builds and runs'],
              <String>['firefox-extension', 'Any host', 'Builds and runs'],
              <String>['linux-cli', 'Linux', 'Runs in a terminal in the '
                  'verification workflow'],
              <String>['windows-cli, macos-cli, fuchsia-cli', 'That OS', 'Not '
                  'verified'],
              <String>['web-server', 'Any host', 'See Servers and deploying'],
            ]),
            DocsText('The evidence for every row, with CI run links, is in '
                'build-targets.md.'),
            ExternalLink('Read build-targets.md', kBuildTargetsUrl),
          ],
        ),
        DocsSection(
          id: 'embedded',
          title: 'TVs and embedded devices use vendor embedders',
          children: <Widget>[
            Bullets(<String>[
              'tizen, sony-elinux, webos, fuchsia and tvos build through the '
                  'platform\'s own Flutter embedder.',
              'Dartvel keeps a pinned fork of each, which it can install for '
                  'you.',
              '--arch picks arm, arm64 (the default) or x64 for embedded '
                  'builds.',
            ]),
            DocsNote('sony-elinux-iso and sony-elinux-img',
                'These names are accepted. Today they build the same bundle as '
                'sony-elinux, with no disk image.'),
            UpstreamCredits(
              ids: <String>['tizen', 'elinux', 'webos', 'fuchsia', 'tvos'],
              lead: 'Thanks to the embedders these targets are built on:',
              link: false,
            ),
          ],
        ),
        DocsSection(
          id: 'terminal',
          title: 'Build for the terminal',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel build linux-cli     # terminal only, no GUI code',
              'dartvel build linux-tui     # the same target',
            ]),
            Bullets(<String>[
              'A -cli build links the terminal renderer and no GUI.',
              'Set dartvel.terminal: true to link both into a normal desktop '
                  'build.',
              'build-targets.md records that terminal builds and native assets '
                  'do not yet compose.',
            ]),
            UpstreamCredit('flt', lead: 'Terminal rendering is built on'),
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
