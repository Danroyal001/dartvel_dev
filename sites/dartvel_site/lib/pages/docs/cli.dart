import 'package:flutter/material.dart';

import '../../components/docs_cli_command.dart';
import '../../components/docs_cli_reference.dart';
import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Dartvel CLI reference: every command and flag', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsCliPage(BuildContext context) => DocsArticle(
      page: DVRoutes.docscli,
      lead: const <String>[
        'Every dartvel command, with its flags, as dartvel --help prints them.',
        'This page is generated from the CLI\'s command table on each change.',
      ],
      sections: <DocsSection>[
        for (final DocsCliCommand command in kCliCommands)
          DocsSection(
            id: command.name,
            title: 'dartvel ${command.name}',
            children: <Widget>[DocsCliEntry(command: command)],
          ),
        const DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('CLI', missing: <String>[
              'No crashes or meters commands, and no deploy --plan or deploy '
                  'rollback.',
              'No preview logs or preview mail.',
              'No application commands declared with an annotation.',
            ]),
          ],
        ),
      ],
    );
