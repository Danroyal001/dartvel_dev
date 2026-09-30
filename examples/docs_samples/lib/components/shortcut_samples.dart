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
