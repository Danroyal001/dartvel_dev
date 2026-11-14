import 'package:flutter/material.dart';

import '../../components/docs_cli_command.dart';
import '../../components/docs_cli_reference.dart';
import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel CLI reference: every command and flag',
  description:
      'Every dartvel command and flag, taken from the CLI itself: '
      'create, dev, build, deploy, db and test, matching what dartvel '
      '--help prints.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsCliPage(BuildContext context) => DocsArticle(
  page: DVRoutes.docscli,
  lead: const <String>[
    'Every dartvel command, with its flags, as `dartvel --help` prints them.',
    'This page is generated from the CLI\'s command table on each change.',
    '`dartvel upgrade` installs the latest packaged CLI after SHA-256 verification. '
        'Framework transaction compensations restore the previous binary and PATH '
        'if installation, PATH configuration or stale-copy cleanup fails. '
        'Open a new terminal to refresh PATH. Windows retires locked old binaries '
        'on a later invocation. `dartvel update` uses the same flow. '
        '`dartvel upgrade --plan` remains a read-only project plan.',
    '`dartvel upgrade --project` moves the Dartvel packages in pubspec.yaml, and '
        'in the project\'s local modules, to the CLI\'s release and resolves them. '
        'From 3.47.0 a Dartvel version is Flutter\'s major and minor followed by '
        'Dartvel\'s own release number; the release before it was 0.13.51, and '
        'a project on 0.13.x moves across with this command, because a caret '
        'on 0.13.51 stops below 0.14.0.',
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
        DocsStatus(
          'CLI',
          missing: <String>[
            'No crashes or meters commands, and no deploy --plan or deploy '
                'rollback.',
            'No branch-deployment logs or captured-mail view.',
            'No application commands declared with an annotation.',
          ],
        ),
      ],
    ),
  ],
);
