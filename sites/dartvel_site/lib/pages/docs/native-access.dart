import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

/// Native platform access through DV.Platform: every member that exists,
/// what each platform supports, permissions, and where the spec plans more.
@DVPage(
  title: 'Native device access',
  description: 'Reach the device through DV.Platform. Every member listed here '
      'exists in code; planned members are marked as planned.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsNativeAccessPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsnativeaccess,
      lead: <String>[
        'DV.Platform is how an application reaches the device it runs on: '
        'native APIs through FFI and JNI, never platform channels.',
        'Every getter below exists in `packages/dartvel_flutter/lib/dartvel_flutter.dart`. '
        'Members listed as planned have no binding yet.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'what-is-it',
          title: 'What it is',
          children: <Widget>[
            DocsText('DV.Platform holds the native capabilities the framework '
                'registers for the current target. A desktop binds clipboard, '
                'window controls and file associations; a phone does not. '
                'A browser has a different set. Calling a capability the '
                'target lacks throws a typed error that names the missing '
                'binding.'),
            DocsText('Bindings are registered through `dart:ffi` (Linux, '
                'Windows, macOS, embedded) or `jnigen`-generated JNI '
                '(Android), and through `dart:js_interop` with `package:web` '
                '(web). No `MethodChannel`, `EventChannel` or '
                '`BasicMessageChannel` is used anywhere.'),
          ],
        ),
        DocsSection(
          id: 'members',
          title: 'Members',
          children: <Widget>[
            DocsSubheading('Platform identity'),
            DocsShell(<String>[
              'DV.Platform.currentPlatform   // android, ios, macos, windows, linux, web, ...',
              'DV.Platform.isAndroid, isIOS, isWeb, isLinux, isMacOS, isWindows',
              'DV.Platform.isTV, isWatch, isFoldable',
              'DV.Platform.breakpoint        // desktop, tablet, mobile',
              'DV.Platform.orientation',
            ]),
            DocsSubheading('Screen and window'),
            DocsShell(<String>[
              'DV.Platform.screen.screenWidth, screenHeight',
              'DV.Platform.screen.safeAreas',
              'DV.Platform.window.setTitle(), .maximize(), .minimize(), .restore(), .setSize()',
            ]),
            DocsSubheading('Device namespaces'),
            DocsText('Every DV.Platform member is lowerCamel, like the rest of '
                '`DV.*`: `DV.Platform.camera`, `DV.Platform.window`, '
                '`DV.Platform.fileStorage`, `DV.Platform.notifications`. The older capitalised names '
                '(`Camera`, `Window`, `Tray`, `FileStorage`, `Notifications` and the rest) '
                'still compile as `@Deprecated` aliases for one release. '
                '`DV.Platform.notifications` unifies the notifications service and device-local notifications under the standard lowerCamel convention.'),
            DocsShell(<String>[
              'DV.Platform.camera, media, location, bluetooth, nfc, clipboard, share',
              'DV.Platform.sensors, biometrics, deepLinks, haptics, contacts',
              'DV.Platform.notifications, permissions, browserExtension, network',
              'DV.Platform.install, display, fileStorage, device',
            ]),
            DocsSubheading('Desktop-only'),
            DocsShell(<String>[
              'DV.Platform.associations  // file associations',
              'DV.Platform.dragDrop',
              'DV.Platform.tray, Menus, Shortcuts, Printing',
            ]),
            DocsSubheading('Surface'),
            DocsShell(<String>[
              'DV.Platform.surface        // DVRenderSurface.gui or .terminal',
              'DV.Platform.terminal',
              'DV.Platform.useRenderSurface(...)',
            ]),
            DocsSubheading('File, storage and notifications proxies'),
            DocsShell(<String>[
              'DV.Platform.fileStorage    // DV.FileStorage on the device disk',
              'DV.Platform.notifications  // proxy to DV.Notifications & local notifications',
            ]),
          ],
        ),
        DocsSection(
          id: 'platform-support',
          title: 'Platform support',
          children: <Widget>[
            DocsText('Availability per member (shipped / partial / planned). '
                'Partial means the getter exists but the underlying native '
                'binding covers only some operations or platforms.'),
            DocsTable(
              columns: <String>['Member', 'Status', 'Platforms with bindings'],
              rows: <List<String>>[
                <String>['surface', 'Shipped', 'all'],
                <String>['terminal', 'Shipped (opt-in)', 'terminal backend linked'],
                <String>['currentPlatform / is*', 'Shipped', 'all'],
                <String>['breakpoint / orientation', 'Shipped', 'all'],
                <String>['screen', 'Shipped', 'all'],
                <String>['Window', 'Shipped', 'all (desktop controls partial)'],
                <String>['tray', 'Shipped', 'macOS, Windows, Linux: separators, headers, check and radio marks, submenus, update in place'],
                <String>['window.hide / .show, close-to-hide', 'Shipped', 'macOS, Windows, Linux (exitPolicy explicit)'],
                <String>['launchAtLogin', 'Shipped', 'macOS 13+, Windows, Linux'],
                <String>['Menus / Shortcuts / Printing', 'Partial', 'Linux, Windows, macOS bindings; availability depends on the desktop session'],
                <String>['Dialogs', 'Partial', 'Linux, Windows, macOS native bindings'],
                <String>['DragDrop', 'Shipped', 'desktop (Linux, Windows, macOS)'],
                <String>['associations', 'Shipped', 'desktop'],
                <String>['camera', 'Partial', 'Android, some web; iOS built, not yet run on an iPhone'],
                <String>['media', 'Partial', 'Android, some web; iOS pickers built, not yet run on an iPhone'],
                <String>['fileStorage', 'Shipped', 'all: Android, iOS, macOS, Windows, Linux, embedded Linux, web (OPFS); pickers on Android, desktop and web'],
                <String>['files (deprecated)', 'Shipped', 'Android, web; use fileStorage'],
                <String>['location', 'Partial', 'Android; iOS built, not yet run on an iPhone'],
                <String>['notifications', 'Stub', 'all'],
                <String>['bluetooth', 'Partial', 'Android 31+, some others'],
                <String>['nfc', 'Partial', 'isAvailable on Android and iOS; reading and writing tags planned'],
                <String>['device', 'Shipped (stub)', 'all'],
                <String>['clipboard', 'Partial', 'web, Linux, Windows, macOS (varies)'],
                <String>['share', 'Partial', 'Android, web; iOS built, not yet run on an iPhone'],
                <String>['sensors', 'Partial', 'Android, some web; iOS built, not yet run on an iPhone'],
                <String>['biometrics', 'Partial', 'web; canAuthenticate on Android; iOS (Face ID, Touch ID) built, not yet run on an iPhone'],
                <String>['deepLinks', 'Stub', 'all'],
                <String>['haptics', 'Partial', 'Android, iOS, web'],
                <String>['contacts', 'Partial', 'Android; iOS built, not yet run on an iPhone'],
                <String>['permissions', 'Shipped', 'all (policy framework)'],
                <String>['browserExtension', 'Shipped', 'Chromium / Firefox extensions'],
                <String>['network', 'Shipped', 'all (signal: online / metered / offline / unknown)'],
                <String>['install', 'Partial', 'web (PWA)'],
                <String>['display', 'Shipped (stub)', 'all'],
              ],
            ),
          ],
        ),
        DocsSection(
          id: 'permissions',
          title: 'Permissions',
          children: <Widget>[
            DocsText('Runtime permissions are requested through '
                '`DV.Platform.permissions`. The framework asks at the point '
                'the capability is first called. Each '
                'permission is mapped to a policy entry in `pubspec.yaml`. '
                'A refusal produces a typed error.'),
            DocsShell(<String>[
              'DV.Platform.permissions.request(\'microphone\')',
            ]),
            DocsNote('Permissions are per-capability',
                'A camera call checks the camera permission; a microphone '
                'call checks the microphone permission. There is no global '
                '"allow all" prompt.'),
          ],
        ),
        DocsSection(
          id: 'beyond-platform',
          title: 'Beyond DV.Platform',
          children: <Widget>[
            DocsText('DV.Platform covers what the framework registers. '
                'Going further requires native modules or direct bindings.'),
            DocsSubheading('Native binding graph'),
            DocsText('The framework binds native APIs through FFI '
                '(C libraries: libX11, GTK, GDBus on Linux; Win32 on Windows; '
                'CoreGraphics on macOS) and through JNI (`jnigen`-generated '
                'bindings on Android). Each platform file in the framework '
                'lists the bindings that are registered and the ones that '
                'are deliberately absent, with the reason stated.'),
            DocsSubheading('Platform channels / FFI'),
            DocsText('No Flutter `MethodChannel` is used for any native '
                'integration. All bindings go through `dart:ffi` or '
                '`package:jni`, per the native integration rule.'),
            DocsSubheading('Platform views'),
            DocsText('Native UI that Flutter cannot render is embedded '
                'through platform views. Their lifecycle and routing '
                'are framework concerns; applications declare what they '
                'need.'),
            DocsSubheading('DVPreferredRenderingMode'),
            DocsText('A planned feature: selecting the render mode '
                '(hardware, software, hybrid) at build time. Selection '
                'is not yet implemented.'),
          ],
        ),
        DocsSection(
          id: 'planned',
          title: 'Planned (not shipped)',
          children: <Widget>[
            DocsText('These members are referenced in the spec but have '
                'no binding registered today. They are listed honestly '
                'as Planned.'),
            Bullets(<String>[
              '`nfc.readTag` needs Android `Activity` dispatch or iOS '
              'CoreNFC entitlement.',
              '`biometrics.authenticate` on Android needs a small Java '
              'shim for its callback.',
              '`bluetooth.isEnabled` needs runtime-granted permission '
              'since API 31.',
              'Additional media/capture bindings requiring `Activity` '
              'context or specific entitlements.',
              'Native modules via `DV.Modules`: mount a Dartvel module '
              'inside a native app (see /docs/adopting and the native-app '
              'section below).',
            ]),
          ],
        ),
      ],
    );
