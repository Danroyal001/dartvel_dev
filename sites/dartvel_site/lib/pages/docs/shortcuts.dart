import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Keyboard shortcuts in Dartvel apps',
  description:
      'Add page or app keyboard shortcuts, protect text input, and '
      'show a shortcut sheet with the question-mark key.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsShortcutsPage(BuildContext context) => const DocsArticle(
  page: DVRoutes.docsshortcuts,
  lead: <String>[
    'Give common actions a keyboard shortcut with DVShortcutScope.',
    'Press ? outside a text field to see the shortcuts available here.',
  ],
  sections: <DocsSection>[
    DocsSection(
      id: 'start',
      title: 'Add shortcuts to a page',
      children: <Widget>[
        DocsCode('shortcuts-simple'),
        DocsText(
          'Import your generated dartvel_client/dartvel_client.dart barrel. '
          'Wrap the page content for page scope, or put the scope in your shared '
          'layout for app scope. In an existing Flutter app, MaterialApp.builder '
          'can wrap its child. The most deeply focused scope handles a matching '
          'shortcut first; leaving that scope removes its shortcuts.',
        ),
        Bullets(<String>[
          'mod means Cmd on macOS and iOS, and Ctrl on other platforms, including the web platform being used.',
          'Use ctrl, cmd (or meta), alt and shift joined with +. Letter keys are case-insensitive; add shift explicitly.',
          'Keys include a–z, 0–9, enter, escape, space, tab, backspace, delete, home, end, pageup, pagedown, up, down, left, right, slash, comma, period, minus, equal and f1–f12.',
          'Unknown keys and duplicate combinations in one scope report an error. A page may intentionally override an app shortcut.',
          'The operating system or browser may reserve a combination before the app receives it. These shortcuts run while the app has focus.',
        ]),
      ],
    ),
    DocsSection(
      id: 'editing',
      title: 'Keep typing safe',
      children: <Widget>[
        DocsText(
          'Shortcuts and the ? sheet stay out of a focused text field by '
          'default. Set allowInTextFields: true only for a command that should '
          'run while editing, such as sending a message with Ctrl+Enter. Text '
          'fields can still handle their own built-in editing keys first.',
        ),
        DocsCode('shortcuts-commands'),
      ],
    ),
    DocsSection(
      id: 'help',
      title: 'See the available shortcuts',
      children: <Widget>[
        DocsText(
          'Press ? to open the keyboard shortcut sheet. It combines the '
          'current scope with its parent scopes and shows a page override once. '
          'Use command labels for readable action names; the compact map form '
          'uses the key combination as its label. Escape, Back, the Close button '
          'or a tap outside closes the sheet.',
        ),
        DocsText(
          'The ? combination is reserved while showHelp is true. Set '
          'showHelp: false if your scope needs to bind that combination itself.',
        ),
      ],
    ),
    DocsSection(
      id: 'data',
      title: 'Save shortcut settings',
      children: <Widget>[
        DocsText(
          'DVShortcut.toJson() and DVShortcut.fromJson() keep settings as '
          'data. An editor such as Studio can write this format later. This '
          'release provides the format and code API; it does not add a Studio '
          'shortcut editor. Each command names an action in the app’s explicit '
          'actions map. Loading settings never runs code.',
        ),
        DocsShell(<String>[
          '{',
          '  "keys": "mod+k",',
          '  "command": "search",',
          '  "label": "Search everything",',
          '  "allowInTextFields": false',
          '}',
        ]),
        DocsText(
          'Store a list of these objects for a scope. Invalid fields, '
          'empty command names, missing action callbacks and conflicting '
          'combinations are rejected. Keep saved command names stable when '
          'renaming labels.',
        ),
        DocsNote(
          'System-wide shortcuts',
          'DV.Platform.Shortcuts and the existing '
              'DVShortcuts service register native system-wide shortcuts. '
              'DVShortcutScope is the widget for keys inside your app.',
        ),
      ],
    ),
  ],
);
