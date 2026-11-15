import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Embed Dartvel in an existing native app',
  description:
      'Build a Dartvel project as an Android library or Apple frameworks '
      'with --brownfield, and start it inside a native app you already have.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsExistingNativeAppsPage(BuildContext context) => const DocsArticle(
  page: DVRoutes.docsexistingnativeapps,
  lead: <String>[
    'Add `--brownfield` to `dartvel build` to get what a native app embeds: '
        'an Android library, or XCFrameworks for iOS and macOS.',
    'It extends Flutter\'s add-to-app, so the host starts the project the '
        'way it would start any Flutter module.',
  ],
  sections: <DocsSection>[
    DocsSection(
      id: 'build',
      title: 'Build the artifact a host embeds',
      children: <Widget>[
        DocsShell(<String>[
          'dartvel build android --brownfield',
          'dartvel build ios --brownfield',
          'dartvel build macos --brownfield',
        ]),
        DocsText(
          'Each command generates the client, then builds the project as a '
          'Flutter module in build/brownfield and leaves the result in '
          'build/brownfield/<target>: a Maven repository for Android, '
          'XCFrameworks for iOS and macOS. Your project is not changed.',
        ),
        Bullets(<String>[
          'Next to the artifact, HOST.md says how the host adds it and which '
              'entry point to start.',
          'iOS and macOS frameworks are built with Xcode, so those two '
              'commands need a Mac, or `--cloud`.',
          'Add `--debug` or `--profile` for another build mode. Release is '
              'the default.',
        ]),
      ],
    ),
    DocsSection(
      id: 'start',
      title: 'Start the project from the host',
      children: <Widget>[
        DocsText(
          'Every project gets an entry point named '
          'dartvelEmbeddedEntry_<package>. Start an engine there, or start '
          'main, which runs the same entry. The project boots as an embedded '
          'entry: no single-instance lock and no window of its own, because '
          'the host owns the process.',
        ),
        DocsText(
          'On Android, start several projects from one FlutterEngineGroup '
          'so each extra engine costs a few megabytes. On iOS and macOS, '
          'call run(withEntrypoint:) on a FlutterEngine.',
        ),
      ],
    ),
    DocsSection(
      id: 'flutter',
      title: 'Adopt an existing Flutter application',
      children: <Widget>[
        DocsShell(<String>['dartvel init', 'dartvel dev']),
        DocsText(
          'init adds Dartvel to a Flutter project, and `dartvel dev` '
          'generates the client. Keep its router or adopt file-based pages. '
          'A Dartvel application can also mount another Dartvel '
          'application with `dartvel add`.',
        ),
        DocsShell(<String>['dartvel add ../checkout']),
      ],
    ),
    DocsSection(
      id: 'planned',
      title: 'Planned host integration',
      children: <Widget>[
        DocsNote(
          'Not yet implemented',
          'Brownfield builds for the web (a script and an element the host '
              'page places), Linux and Windows. The CLI refuses those '
              'targets with the reason instead of building an app a host '
              'cannot embed.',
        ),
        Bullets(<String>[
          'A generated, typed host API: mount and unmount routes, and '
              'messages both ways.',
          'Host back navigation, lifecycle and verified session hand-off.',
          'Several projects in one module (--integrated), and projects on '
              'different versions side by side.',
        ]),
        DocsText(
          'The Brownfield section in NEW_SPEC.md records the full design and '
          'the order it is built in.',
        ),
      ],
    ),
  ],
);
