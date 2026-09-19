import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';

// What Studio is, split the way it ships: the free Studio in every app and in
// the web-server binary, then Studio Pro from the private dartvel_enterprise
// repository, with the workflow builder given its own section because it is
// the part of Pro a buyer is paying for.
//
// Every claim is checked against the code. The free cards take their badges
// from the spec index through SiteCard(section:), and the Pro cards are held
// to dartvel_studio_pro by test/studio_page_test.dart. The workflow and the
// Dart it exports are what DVWorkflowDocument.toDartSource() printed for that
// workflow, and the screenshots are of the real Studio.
@DVPage(
  title: 'Dartvel Studio and Studio Pro',
  showAppBar: false,
  sitemap: DVPageSitemap(
    priority: 0.8,
    changeFrequency: DVSitemapChangeFrequency.monthly,
  ),
)
@pragma('vm:entry-point')
Widget _studioPage(BuildContext context) => const SingleChildScrollView(
  child: DVBox.list(<Widget>[
    Section(
      glow: true,
      children: <Widget>[
        Eyebrow('DARTVEL STUDIO'),
        Heading(
          'Run your app\'s pages and data from a browser, and keep the code.',
          level: 1,
        ),
        Bullets(<String>[
          'Studio is free. It runs inside your web-server binary at /__studio, '
              'and never inside an app.',
          'Build pages visually and edit model records without writing an '
              'admin panel.',
          'Studio Pro adds a visual workflow builder that exports plain Dart.',
        ]),
        StudioShot(
          'assets/studio/page-builder.png',
          'Dartvel Studio page builder with the Layers tree, a selected '
              'heading on the canvas and the inspector',
          caption: 'The page builder served by a web-server binary: Layers on '
              'the left, the selected heading on the canvas, its styles on the '
              'right.',
        ),
      ],
    ),
    Section(
      tint: true,
      children: <Widget>[
        Eyebrow('FREE STUDIO'),
        Heading('Open Studio on your live server with one grant.'),
        CodeBlock(<String>[
          '# pubspec.yaml',
          'dartvel:',
          '  admin:',
          '    enabled: true',
          '',
          r'$ dartvel build web-server',
          r'$ dartvel admin grant <user-id> --database dartvel_data/data.db',
          '# sign in to your app, then open https://your-host/__studio',
        ]),
        Bullets(<String>[
          'Only people you grant can open it. A visitor who is not signed in '
              'gets the same answer as a page that does not exist.',
          'Edit model records in a form. An edit made against a row that '
              'changed after you opened it is refused.',
          'While you work, dartvel dev serves Studio too, and prints the '
              'private link that opens it.',
        ]),
        StudioShot(
          'assets/studio/model-records.png',
          'Dartvel Studio Data section listing Product records with one '
              'open in an edit form',
          caption: 'Data: each record of a model, and a form typed from its '
              'fields.',
        ),
      ],
    ),
    Section(
      children: <Widget>[
        Eyebrow('PAGE BUILDER'),
        Heading('Drag a page together, then keep it as an ordinary @DVPage.'),
        Bullets(<String>[
          'Insert text, images, buttons, spacers and dividers, and arrange '
              'them in columns, rows, wraps, grids and stacks.',
          'Select a node on the canvas or in Layers, style it in the '
              'inspector, preview phone, tablet and desktop widths, and undo '
              'any step.',
          'Code shows the page as an @DVPage file you can keep in your '
              'repository.',
        ]),
        StudioShot(
          'assets/studio/deploy-menu.png',
          'The Deploy button open on its menu: Deploy now, and Restore '
              'original page',
          caption: 'Deploy puts the page live. Its menu also restores the page '
              'from your last build.',
        ),
        Objection(
          'Does deploying a page need a rebuild?',
          'No. On your web-server, a deployed page takes over its route '
              'without a rebuild. Restore original page brings the compiled one '
              'back. '
              'Studio stays on your server. Apps never carry it.',
        ),
      ],
    ),
    Section(
      tint: true,
      children: <Widget>[
        Eyebrow('IN THE FREE STUDIO'),
        Heading('Records, routes and review in the same place as your pages.'),
        DVBox.wrapLine(<Widget>[
          SiteCard(
            'Pages',
            'Insert, Layers, the inspector, undo and redo, deploy, restore and '
                'code export.',
            section: 'Dartvel Studio',
          ),
          SiteCard(
            'Data',
            'Browse and edit each model\'s records. Sensitive fields never '
                'leave the server.',
            section: 'Admin, Devtools, and Scaffolding',
          ),
          SiteCard(
            'Site map, Backend and Tasks',
            'Your pages, backend functions and background tasks, read from '
                'your build, each with the file it was declared in.',
            section: 'Admin, Devtools, and Scaffolding',
          ),
          SiteCard(
            'Team',
            'Lists who may open Studio. Grant and revoke run on the server '
                'with dartvel admin.',
            section: 'Admin, Devtools, and Scaffolding',
          ),
          SiteCard(
            'Content review',
            'Draft, review and schedule a page, with who approved which '
                'version and signed preview links. The editor is built '
                'and is not in the server Studio yet.',
            section: 'Content Workflow',
          ),
          SiteCard(
            'Queue and Cache',
            'See waiting and failed jobs per queue, and the cache tags your '
                'app has set.',
            section: 'Queues, Jobs, and Signals',
          ),
        ], spacing: 16),
      ],
    ),
    Section(
      children: <Widget>[
        Eyebrow('FROM THE SAME GRAPH'),
        Heading('Docs and public pages come from what Studio reads.'),
        DVBox.wrapLine(<Widget>[
          SiteCard(
            'dartvel inspect and dartvel mcp',
            'Print the models, routes, functions and jobs Studio shows, or '
                'hand them to a coding agent.',
            section: 'Admin, Devtools, and Scaffolding',
          ),
          SiteCard(
            'Project docs',
            'dartvel docs writes a static site of your models, functions, '
                'routes, jobs and policies. It is not served inside your app '
                'yet.',
            section: 'Documentation Generation',
          ),
          SiteCard(
            'Model pages',
            '@DVModel(generatePublicPages: true) gives each record a public '
                'page with head tags and structured data. A row\'s featured '
                'image does not become its favicon yet.',
            section: 'Generated Model Pages',
          ),
        ], spacing: 16),
      ],
    ),
    Section(
      dark: true,
      children: <Widget>[
        Eyebrow('STUDIO PRO', onDark: true),
        Heading('Studio Pro adds a workflow builder, Figma import and team '
            'review.', onDark: true),
        Bullets(onDark: true, <String>[
          'Pro is paid, and lives in the private dartvel_enterprise '
              'repository.',
          'Each Pro feature adds a section to Studio, so the free Studio '
              'never shows a tab it cannot open.',
        ]),
      ],
    ),
    Section(
      children: <Widget>[
        Eyebrow('WORKFLOW BUILDER'),
        Heading('Build a backend function from steps, then export it as Dart.'),
        Bullets(<String>[
          'Drag Call, Set, Condition and Return steps onto the canvas. A Call '
              'runs an action you registered with DVWorkflows.registerAction.',
          'Deploy saves the workflow. From saving on, DVWorkflows.run '
              'executes it.',
          'Export writes an ordinary @DVBackendFunction, so you can '
              'drop the builder whenever you like.',
        ]),
        StudioShot(
          'assets/studio/workflow-builder.png',
          'Studio Pro workflow builder showing the welcomeCustomer workflow '
              'as Set, Call, Condition and Return steps',
          caption: 'The welcomeCustomer workflow in Studio Pro. Its steps:',
        ),
        CodeBlock(<String>[
          '# welcomeCustomer(email, wantsNews)',
          "SET        subject = 'Thanks for joining Oakline Coffee'",
          'CALL       sendWelcome(to: email, subject: subject) -> receipt',
          'CONDITION  wantsNews',
          '  then     CALL addToNewsletter(email: email)',
          'RETURN     receipt',
        ]),
        Body('Export writes this file, and nothing in it refers to the '
            'builder:'),
        CodeBlock(<String>[
          "import 'package:dartvel_core/dartvel.dart';",
          '',
          '// Exported from Dartvel Studio. Ordinary backend function:',
          '// edit freely, the builder is no longer involved.',
          '@DVBackendFunction()',
          "@pragma('vm:entry-point')",
          'Future<Object?> _welcomeCustomer(Object? email, Object? wantsNews) => welcomeCustomerBody(email, wantsNews);',
          '',
          'Future<Object?> welcomeCustomerBody(Object? email, Object? wantsNews) async {',
          "  final subject = 'Thanks for joining Oakline Coffee';",
          '  final receipt = await sendWelcome(to: email, subject: subject);',
          '  if (wantsNews == true) {',
          '    await addToNewsletter(email: email);',
          '  }',
          '  return receipt;',
          '}',
        ]),
        Objection(
          'What if a step names an action that does not exist?',
          'The run stops and names the step. A missing variable does the same, '
              'so a typo never sends mail to nobody and reports success.',
        ),
      ],
    ),
    Section(
      tint: true,
      children: <Widget>[
        Eyebrow('ALSO IN STUDIO PRO'),
        Heading('Bring in a design, reuse it and review it as a team.'),
        DVBox.wrapLine(<Widget>[
          SiteCard(
            'Workflow builder',
            'Call, Set, Condition and Return steps, run as saved and exported '
                'as a @DVBackendFunction.',
            built: true,
          ),
          SiteCard(
            'Figma import',
            'Every top-level frame becomes a page. Auto-layout, type, '
                'shadows, gradients and icons come through, and images are '
                'downloaded before Figma\'s links expire.',
            built: true,
          ),
          SiteCard(
            'Reusable components',
            'Save a node as a component, see how many pages use it, and push '
                'a change to every instance.',
            built: true,
          ),
          SiteCard(
            'Revision history',
            'Every save is numbered and credited. Compare a revision with the '
                'page, then restore it.',
            built: true,
          ),
          SiteCard(
            'Multi-user editing and approval',
            'Editors see each other\'s changes over a transport you connect. '
                'An editor\'s Deploy waits for an approver, and both are in '
                'the audit trail.',
            built: true,
          ),
          SiteCard(
            'Enterprise SSO',
            'SAML, SCIM provisioning and directory sync for your team.',
            built: false,
          ),
        ], spacing: 16),
      ],
    ),
    Section(
      children: <Widget>[
        Eyebrow('START'),
        Heading('Open the free Studio on your own app today.'),
        CodeBlock(<String>[
          'dartvel create shop',
          'cd shop && dartvel build web-server',
        ]),
        Objection(
          'Do I need Pro to build pages visually?',
          'No. The page builder, model records and code export are free with '
              'every Dartvel project.',
        ),
        DVBox.wrapLine(<Widget>[
          PrimaryLink('Create your first app', '/docs'),
          GhostLink('Deploy the web-server binary', '/docs/deploying'),
        ], spacing: 12),
      ],
    ),
    SiteFooter(),
  ], spacing: 0),
);
