import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Coding agents: rules every agent reads',
  description:
      'dartvel create and dartvel init set up AGENTS.md, CLAUDE.md, '
      'GEMINI.md, the Cursor rules, Copilot instructions and the rest, from '
      'one generated block that dartvel dev keeps matched to the Dartvel '
      'version you have installed.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsAgentsPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsagents,
      lead: <String>[
        'Every coding agent you open the project in gets the same rules, from '
            'one generated block.',
        '`dartvel dev` keeps that block matched to the Dartvel version you '
            'have installed, and never touches the text around it.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'setup',
          title: 'What gets written',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel create my_app     # writes the agent files',
              'dartvel init              # same, for a project you already had',
              'dartvel dev               # refreshes them',
            ]),
            DocsText('One file per tool, so no agent is left guessing:'),
            DocsTable(columns: <String>[
              'File',
              'Read by',
            ], rows: <List<String>>[
              <String>['AGENTS.md', 'Codex, OpenCode, Devin, ChatGPT, and '
                  'anything that reads AGENTS.md'],
              <String>['CLAUDE.md', 'Claude Code'],
              <String>['GEMINI.md', 'Gemini CLI'],
              <String>['.cursor/rules/dartvel.mdc', 'Cursor, with '
                  'alwaysApply'],
              <String>['.cursorrules', 'Cursor\'s project rules file'],
              <String>['.windsurfrules', 'Windsurf'],
              <String>['.clinerules', 'Cline'],
              <String>['.kiro/steering/dartvel.md', 'Kiro'],
              <String>['.github/copilot-instructions.md',
                  'GitHub Copilot and ChatGPT in a repository'],
              <String>['CONVENTIONS.md', 'aider, and tools that read a '
                  'conventions file'],
              <String>['AGENT.md', 'agents that read the singular name'],
              <String>['.aider.conf.yml', 'aider, told which files to read'],
            ]),
            DocsNote('Codex, OpenCode and Devin get no file of their own',
                'They read AGENTS.md from the project root. Four more copies '
                'would be four more files that can disagree, so AGENTS.md says '
                'which tools it serves instead.'),
          ],
        ),
        DocsSection(
          id: 'block',
          title: 'The block, and what it will not touch',
          children: <Widget>[
            DocsShell(<String>[
              '<!-- dartvel:begin agents -->',
              '... the rules, the version, where to read more',
              '<!-- dartvel:end agents -->',
            ]),
            Bullets(<String>[
              'Everything inside the markers is Dartvel\'s and is replaced on a '
                  'refresh.',
              'Everything outside them is yours. A rule you wrote above the '
                  'block is still there after the next `dartvel dev`.',
              'A file that had no block gains one below its existing text, so a '
                  'CLAUDE.md you wrote before Dartvel is not overwritten.',
              'A file you deleted by hand comes back, because create set the '
                  'agent up.',
              'Nothing is printed when a refresh changed nothing. A line on '
                  'every start is a line people learn to ignore.',
              'A refresh happens on every `dartvel dev`, whichever mode it '
                  'runs in. A command whose arguments it rejects writes '
                  'nothing at all.',
            ]),
          ],
        ),
        DocsSection(
          id: 'version',
          title: 'Matched to your version',
          children: <Widget>[
            DocsText('The block names the Dartvel you are running and points at the '
                'documentation shipped with that exact version, so an agent '
                'reads the API as this version has it. The newest website '
                'describes whatever version is newest.'),
            DocsText('When the documentation is not beside the installed '
                'package, the block says so and names `dartvel docs` instead. '
                'It never prints a path that does not exist.'),
            DocsShell(<String>[
              'dartvel upgrade --plan',
              'dartvel dev',
            ]),
            DocsText('After an upgrade, the next `dartvel dev` refreshes the '
                'block. Nothing else to run.'),
          ],
        ),
        DocsSection(
          id: 'docs',
          title: 'Your own rules, and the project\'s own reference',
          children: <Widget>[
            Bullets(<String>[
              'Put the house rules outside the block, at the top of AGENTS.md. '
                  'They survive every refresh.',
              '`dartvel docs` builds a reference from this project\'s graph: '
                  'its routes, data models, backend functions, jobs, policies '
                  'and modules. It is more accurate than anything written for '
                  'every project, because it is about this one.',
              '`dartvel mcp` serves the same graph to a coding agent, read-only.',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Coding Agent Documentation', missing: <String>[
              'No opinionated architecture documents written into the project: '
                  'initialisation, data, HTTP, UI, naming, setup, Git and '
                  'process are not scaffolded yet.',
              'No SKILL.md files shipped per module, and no '
                  '`dartvel agent skills sync`.',
              'No `dartvel agent` command: nothing starts the app, screenshots '
                  'it or stops it.',
              'No llms.txt or llms-full.txt for web builds.',
              'The block points at one rules document. It does not enumerate '
                  'the project\'s own pages, models or API.',
            ]),
          ],
        ),
      ],
    );