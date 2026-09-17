import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Dartvel AI: chat, structured output, embeddings and tools', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsAiPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsai,
      lead: <String>[
        'Call Anthropic, OpenAI, Gemini, OpenRouter or a local Ollama model '
            'through one API, DV.AI.',
        'Turn a backend function into a tool a model can call, with the JSON '
            'Schema written for you.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'configure',
          title: 'Pick a provider',
          children: <Widget>[
            DocsCode('ai-configure'),
            DocsTable(columns: <String>[
              'Adapter',
              'Calls',
            ], rows: <List<String>>[
              <String>['AnthropicDVAIAdapter', 'Anthropic. No embeddings or '
                  'transcription'],
              <String>['OpenAIDVAIAdapter', 'OpenAI, including Whisper for '
                  'transcription'],
              <String>['OpenRouterDVAIAdapter', 'OpenRouter, with the OpenAI '
                  'request shape'],
              <String>['GeminiDVAIAdapter', 'Google Gemini'],
              <String>['OllamaDVAIAdapter', 'A local Ollama server, '
                  'localhost:11434 by default'],
              <String>['LocalDVAIAdapter', 'Nothing. A predictable answer for tests '
                  'and offline work'],
            ]),
            DocsText('Nothing picks a provider for you. Call configure once at '
                'start-up, or every call throws.'),
          ],
        ),
        DocsSection(
          id: 'call',
          title: 'Chat, extract and embed',
          children: <Widget>[
            DocsCode('ai-chat'),
            Bullets(<String>[
              'structuredOutput takes a JSON Schema and returns a map in that '
                  'shape.',
              'embed returns a vector you can store and search.',
              'transcribe and runAgent are there too. A provider that cannot do '
                  'one throws UnsupportedError.',
            ]),
          ],
        ),
        DocsSection(
          id: 'tools',
          title: 'Let a model call your code',
          children: <Widget>[
            DocsCode('ai-tool'),
            Bullets(<String>[
              'dartvel routes writes a JSON Schema and a handler for each public '
                  '@DVAITool function under lib/backend.',
              'The generated backend registers every tool before it serves.',
              'An argument of the wrong type is refused by name, so a tool '
                  'never runs on a guessed value.',
            ]),
            DocsNote('Serve your tools over MCP',
                'DVMcpServer answers tools/list and tools/call for the '
                'registered tools, and DVMcpClient adopts the tools of another '
                'MCP server. dartvel mcp is a different server: it lets a '
                'coding agent read your project\'s routes, models and jobs.'),
          ],
        ),
        DocsSection(
          id: 'operations',
          title: 'Run a prompt with a budget and a fallback',
          children: <Widget>[
            DocsCode('ai-feature'),
            Bullets(<String>[
              'Prompts are versioned. A stored override can be rolled back, and '
                  'every change is kept in an audit list.',
              'A budget is a usage meter checked before the call. A budgeted '
                  'run needs an idempotency key, so a retry is counted once.',
              'The result says what happened: answered, degraded, refused by the '
                  'budget, or unavailable.',
            ]),
            DocsText('DVAIEval replays golden transcripts against a feature and '
                'fails when too few match.'),
            DocsStatus('AI Operations', missing: <String>[
              'Prompts and features are registered in code. No generator reads '
                  '@DVPrompt or @DVAIFeature, and nothing is wired into DV.AI.',
              'The prompt store is in memory, and there is no dartvel ai eval '
                  'command.',
              'Tokens are estimated at 4 characters each, since adapters report '
                  'no usage.',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('AI', missing: <String>[
              'A tool\'s schema has a type per parameter and no descriptions or '
                  'enums.',
              'A tool that returns a type DVJsonCodec cannot encode throws when '
                  'the result is sent.',
            ]),
          ],
        ),
      ],
    );
