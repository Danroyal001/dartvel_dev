import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

// What an app does on the device it runs on: native APIs through DV.Platform,
// home screen widgets, kiosks, windows and tabs, and desktop features such as
// trays, menus and drag and drop. Status boxes follow docs/spec-status.json.
@DVPage(
  title: 'Dartvel on devices: windows, widgets, kiosks and desktop',
  description: 'Reach native features through DV.Platform on every target: '
      'home screen widgets, kiosks, windows, tabs, foldables and '
      'desktop trays, declared in Dart.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsDevicesPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsdevices,
      lead: <String>[
        'Native features come through DV.Platform on every target, and a '
            'target that lacks one says so instead of failing quietly.',
        'Home screen widgets, kiosks, windows, tabs and desktop trays are '
            'declared in Dart like the rest of your app.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'platform',
          title: 'Call native features through DV.Platform',
          children: <Widget>[
            Bullets(<String>[
              'Each target binds the native features it actually has, through '
                  'FFI or JNI, never platform channels. A tray exists on a '
                  'desktop and not in a browser.',
              'Before you rely on a feature, check capability. Calling one '
                  'the target lacks is an error that names it.',
              'Linux binds the most today and iOS the fewest. CI checks every '
                  'claimed binding against its handler on a real device.',
            ]),
            DocsCode('devices-platform'),
            DocsStatus('Platform', missing: <String>[
              'On Android, biometrics and NFC tags are not bound yet.',
              'iOS binds only a handful of features so far.',
            ]),
          ],
        ),
        DocsSection(
          id: 'home-widgets',
          title: 'Put a widget on the home screen',
          children: <Widget>[
            Bullets(<String>[
              'Annotate a widget with @DVHomeWidget and the build adds it to '
                  'the home screen, with a route that opens the app at it.',
              'Android and iOS widgets are packaged by `dartvel build`. A target '
                  'with nowhere to put one leaves it out and tells you.',
            ]),
            DocsCode('devices-home-widget'),
            DocsStatus('Home Widgets'),
          ],
        ),
        DocsSection(
          id: 'kiosk',
          title: 'Lock a screen to your app',
          children: <Widget>[
            Bullets(<String>[
              'A kiosk policy sets the exit PIN, the idle timeout and what is '
                  'cleared between visitors. `dartvel doctor` refuses a policy '
                  'the target cannot honour.',
              'After the idle warning the session resets: what the policy names '
                  'is cleared, and the app goes home.',
              'System key combinations that leave the app are blocked on Linux '
                  'and Android lock task mode. Accessibility keys still work.',
            ]),
            DocsStatus('Kiosk Mode'),
          ],
        ),
        DocsSection(
          id: 'windows',
          title: 'Open more windows and tabs',
          children: <Widget>[
            Bullets(<String>[
              'DV.Platform.Window.open opens a page in its own window on Linux, '
                  'once: opening it again focuses the one that is open. A second '
                  'launch of the app hands its arguments to the first.',
              'Tab workspaces keep tabs in order, let you drag one out into a '
                  'window where the target allows it, and restore them per '
                  'user and tenant.',
              'On a TV the tabs become tiles the remote moves between.',
            ]),
            DocsCode('devices-window'),
            DocsStatus('Multi-Window'),
            DocsStatus('Tab Workspaces'),
          ],
        ),
        DocsSection(
          id: 'foldables',
          title: 'Lay out around the fold on a foldable',
          children: <Widget>[
            Bullets(<String>[
              'On a foldable the first pane sits on one side of the fold and '
                  'the second on the other, with nothing in the hinge. With no '
                  'fold they sit side by side on a tablet and stack on a phone.',
              'context.screen.folds lists each fold with where it is and '
                  'whether it hides pixels. posture is book, tabletop or flat.',
              'Android foldables report their folds today. The iPhone Duo is '
                  'next: its fold comes from iOS 27.1, which needs a binding '
                  'built against that SDK.',
            ]),
            DocsCode('devices-foldable'),
          ],
        ),
        DocsSection(
          id: 'desktop',
          title: 'Trays, menus, shortcuts and drag and drop',
          children: <Widget>[
            Bullets(<String>[
              'Add a tray icon with a menu, app menus and global shortcuts on '
                  'Linux, Windows and macOS.',
              'A window can accept dropped files or text, and gets what was '
                  'dropped and where.',
              'Native print and file dialogs are bound on Linux first.',
            ]),
            DocsCode('devices-desktop'),
            DocsStatus('Desktop, Embedded, and Qt-Critical Capabilities'),
          ],
        ),
      ],
    );
