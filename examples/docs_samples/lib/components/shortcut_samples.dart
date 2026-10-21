import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

Widget shortcutPage(
  Widget pageContent,
  VoidCallback openSearch,
  VoidCallback newNote,
) =>
    // docs:start shortcuts-simple
    DVShortcutScope({
      'mod+k': openSearch,
      'alt+n': newNote,
    }, child: pageContent);
// docs:end

Widget messagePage(
  Widget pageContent,
  VoidCallback openSearch,
  VoidCallback sendMessage,
) =>
    // docs:start shortcuts-commands
    DVShortcutScope.commands(
      const [
        DVShortcut(
          keys: 'mod+k',
          command: 'search',
          label: 'Search everything',
        ),
        DVShortcut(
          keys: 'ctrl+enter',
          command: 'send',
          label: 'Send message',
          allowInTextFields: true,
        ),
      ],
      actions: {'search': openSearch, 'send': sendMessage},
      child: pageContent,
    );
// docs:end

Widget fileRow(Widget row, ValueChanged<String> onAction) =>
    // docs:start context-menu
    DVContextMenu(
      items: const [
        DVMenuItem(id: 'open', label: 'Open'),
        DVMenuItem(id: 'rename', label: 'Rename', shortcut: 'mod+r'),
        DVMenuItem(id: 'share', label: 'Share', children: [
          DVMenuItem(id: 'share.link', label: 'Copy link'),
        ]),
        DVMenuItem(id: 'delete', label: 'Delete'),
      ],
      onSelected: onAction,
      child: row,
    );
// docs:end
