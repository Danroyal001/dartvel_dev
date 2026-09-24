import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

// Modules: a whole Dartvel app mounted inside another at a path, and the
// signing and capability checks that decide whether a published one can be
// trusted. Status boxes follow docs/spec-status.json.
@DVPage(
  title: 'Dartvel modules: mount one app inside another',
  description: 'A Dartvel module is a complete app with its own pages, models '
      'and backend. Mount it at a path and the parent serves all of '
      'it, signed and scope-checked.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsModulesPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsmodules,
      lead: <String>[
        'A module is a complete Dartvel app with its own pages, models and '
            'backend. Mount it at a path and the parent serves all of it.',
        'A published module is signed, and it declares what it may reach. The '
            'build checks both before it mounts it.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'mount',
          title: 'Mount a module at a path',
          children: <Widget>[
            DocsShell(<String>[
              '# pubspec.yaml',
              'dartvel:',
              '  modules:',
              '    notes:',
              '      source:',
              '        path: modules/notes',
              '      mount: /notes',
              '      deployment: embedded',
            ]),
            Bullets(<String>[
              'The module\'s own /view/:id is served at /notes/view/:id. Its '
                  'backend functions, schedules and AI tools join the '
                  'parent\'s, and dartvel db migrate creates its tables.',
              'The parent reaches it as DV.Modules.notes, with paths resolved '
                  'against wherever it is mounted, so the module never names '
                  'its own mount point.',
              'Two functions on one path, or two models on one table, stop the '
                  'build instead of one quietly winning.',
            ]),
            DocsShell(<String>['dartvel modules list']),
          ],
        ),
        DocsSection(
          id: 'trust',
          title: 'Publish a signed module, and pin what you mount',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel modules publish --key signing.key --key-id acme',
              'dartvel modules pin',
              'dartvel doctor --modules',
            ]),
            Bullets(<String>[
              'publish reads the capabilities your code uses, such as the '
                  'domains it calls and the secrets it reads, and refuses when '
                  'they differ from what you declared. Then it signs and '
                  'publishes to pub.dev.',
              'pin writes dartvel.module.lock with each module\'s version, '
                  'digest, signing key and publisher. A changed key, a '
                  'stripped signature or an older version stops the build.',
              'The parent grants each module\'s capabilities under '
                  'dartvel.modules. A module that uses more than it was '
                  'granted is refused.',
            ]),
          ],
        ),
        DocsSection(
          id: 'sources',
          title: 'Where a module can come from',
          children: <Widget>[
            DocsText('A module is also how capability from outside Dart '
                'reaches an application. Every capability a product needs '
                'already exists behind somebody\'s SDK, so one command '
                'resolves any of them and what comes back is always a '
                'module.'),
            Bullets(<String>[
              'One command will take a Dartvel project, a Maven artifact, a '
                  'Rust crate, an npm package, a Swift package, a WASM '
                  'binary, or an OpenAPI, GraphQL or gRPC document. It does '
                  'not exist yet, so this page shows no shell for it.',
              'A source that is already a Dartvel project is mounted '
                  'directly. Nothing is wrapped, because wrapping a module '
                  'that is already a module adds a layer whose only job is '
                  'to be walked through.',
              'Anything else becomes a generated module: an ordinary Dart '
                  'package with a public surface, native implementations for '
                  'the targets it supports, and generated tests.',
              'Where an implementation ends up follows the call sites, never '
                  'the language it was written in. One Rust crate ships as a '
                  'library on a phone, as WASM on the web and inside the '
                  'backend binary, chosen per environment.',
              'For every environment a module is called from it declares '
                  'real, compat, noop or unavailable. There is no fifth '
                  'answer and no default: a module called from somewhere it '
                  'says nothing about stops the build.',
              'OpenAPI, GraphQL and gRPC produce pure Dart over DV.Http. '
                  'There is no binding and no foreign runtime at all.',
            ]),
            DocsNote('None of this is built yet',
                'The lockfile already pins a foreign source, because a pin '
                'has to exist before anything can be resolved into one. '
                'Everything else here is a specified surface with no code '
                'behind it.'),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Modules', missing: <String>[
              'A module that runs in its own deployment contributes no '
                  'backend to the parent build, by design.',
            ]),
            DocsStatus('Module Sources'),
            DocsStatus('Native Binding Graph'),
            DocsStatus('Module Health'),
            DocsStatus('Module Distribution and Trust', missing: <String>[
              'Capabilities are checked at build time only. A running module\'s '
                  'network and secret access are not checked yet.',
              'Nothing calls pub.dev to verify the publisher, so without a '
                  'registry lookup it is recorded as unverified.',
            ]),
          ],
        ),
      ],
    );
