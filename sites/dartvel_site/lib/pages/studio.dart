import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';

// What Studio is, split the way it ships: the free Studio in every app and in
// the web-server binary, then Studio Pro from the private dartvel_enterprise
// repository, which comes with Dartvel Cloud, with the frontend and backend
// function builders given their own section because they are the part of Pro
// a buyer is paying for.
//
// Every claim is checked against the code. The free cards take their badges
// from the spec index through SiteCard(section:), and the Pro cards are held
// to dartvel_studio_pro by test/studio_page_test.dart. The Dart the functions
// export is what DVWorkflowDocument.toDartSource() printed for them, and the
// screenshots are of the real Studio.
@DVPage(
  title: 'Dartvel Studio and Studio Pro',
  description: 'Dartvel Studio is the visual builder for a Dartvel app: pages, '
      'models, backend functions, modules and deploys, in the browser '
      'and on a phone.',
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
      grain: true,
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
          'Studio Pro comes with Dartvel Cloud, and adds frontend and '
              'backend functions built from steps and exported as plain Dart.',
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
          'Studio fits a phone: sections move to a bar along the bottom, and '
              'the editor shows Elements, Page or Style one at a time.',
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
          'Deploy sends the page to your website, phone and tablet apps, '
              'desktop apps, TVs, browser extensions and devices, or only the '
              'ones you tick.',
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
          'No. The website shows a deployed page at once, and apps get it '
              'from your server the next time they open. Restore original page '
              'brings the compiled one back. '
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
            'Frontend and Backend',
            'Build a function from steps on either side, and see the backend '
                'functions your code already declares.',
            section: 'Dartvel Studio',
          ),
          SiteCard(
            'Site map and Tasks',
            'Your pages and background tasks, read from your build, each with '
                'the file it was declared in.',
            section: 'Admin, Devtools, and Scaffolding',
          ),
          SiteCard(
            'Modules',
            'The modules your app mounts: where each is served, where it came '
                'from and whose tables it uses. One the build could not mount '
                'says so, with the reason.',
            section: 'Modules',
          ),
          SiteCard(
            'Team',
            'Lists who may open Studio. Grant and revoke run on the server '
                'with `dartvel admin`.',
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
            '`dartvel inspect` and `dartvel mcp`',
            'Print the models, routes, functions and jobs Studio shows, or '
                'hand them to a coding agent.',
            section: 'Admin, Devtools, and Scaffolding',
          ),
          SiteCard(
            'Project docs',
            '`dartvel docs` writes a static site of your models, functions, '
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
      children: <Widget>[
        Eyebrow('FRONTEND AND BACKEND FUNCTIONS'),
        Heading('Build what a button does and what the server does, from the '
            'same steps. Free.'),
        Bullets(<String>[
          'Frontend functions run in the app and backend functions on your '
              'server, each in its own Studio section. A frontend function '
              'calls a backend one by name.',
          'Inputs and results have types, Text, Whole number, Number or Yes '
              'or no, and a run refuses the wrong type before any step runs.',
          'Both builders are free: a page builder whose buttons can do '
              'nothing is not a page builder. Deploy saves the function, and '
              'Export writes ordinary Dart, so you can drop the builder.',
        ]),
        StudioShot(
          'assets/studio/frontend-function.png',
          'The Frontend section of Studio with the orderAhead function open: '
              'Set, Call, Condition and Return steps on the canvas, and its '
              'typed inputs on the right',
          caption: 'A frontend function: what a button does, built from '
              'steps, with its inputs typed.',
        ),
        StudioShot(
          'assets/studio/backend-function.png',
          'The Backend section with the placeOrder function open, and the '
              'backend functions the project wrote in code listed underneath '
              'by the address each answers',
          caption: 'The Backend section builds one and lists the ones your '
              'code already declares.',
        ),
        Body('Export writes this backend function, and nothing in it refers '
            'to the builder:'),
        CodeBlock(<String>[
          "import 'package:dartvel_core/dartvel.dart';",
          '',
          '// Exported from Dartvel Studio. Ordinary backend function:',
          '// edit freely, the builder is no longer involved.',
          '@DVBackendFunction()',
          "@pragma('vm:entry-point')",
          'Future<String> _welcomeCustomer(String email, bool wantsNews) => welcomeCustomerBody(email, wantsNews);',
          '',
          'Future<String> welcomeCustomerBody(String email, bool wantsNews) async {',
          "  final subject = 'Thanks for joining Oakline Coffee';",
          '  final receipt = await sendWelcome(to: email, subject: subject);',
          '  if (wantsNews == true) {',
          '    await addToNewsletter(email: email);',
          '  }',
          '  return receipt;',
          '}',
        ]),
        Body('A frontend function built in the Frontend section calls it '
            'through the generated client:'),
        CodeBlock(<String>[
          "import '../dartvel_client/dartvel_client.dart';",
          '',
          '// Exported from Dartvel Studio. Ordinary frontend function:',
          '// it runs in the app, and calls backend functions through',
          '// the generated client. Edit freely, the builder is no',
          '// longer involved.',
          'Future<String> joinOakline(String email, bool wantsNews) async {',
          '  final receipt = await welcomeCustomer(email: email, wantsNews: wantsNews);',
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
      dark: true,
      children: <Widget>[
        Eyebrow('STUDIO PRO', onDark: true),
        Heading('Studio Pro adds Figma import, components and team review.',
            onDark: true),
        Bullets(onDark: true, <String>[
          'Studio Pro comes with Dartvel Cloud. There is nothing separate to '
              'buy, and it is not in your web-server binary.',
          'Each Pro feature adds a section to Studio, so the free Studio '
              'never shows a tab it cannot open.',
        ]),
      ],
    ),
    Section(
      tint: true,
      children: <Widget>[
        Eyebrow('ALSO IN STUDIO PRO'),
        Heading('Bring in a design, reuse it and review it as a team.'),
        DVBox.wrapLine(<Widget>[
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
      tint: true,
      children: <Widget>[
        Eyebrow('EVERY SECTION'),
        Heading('All ten sections, photographed from a Studio that was run.'),
        Body('Each picture below was taken by `dartvel capture studio` against a '
            'web-server binary built from this repository: it signs in, clicks '
            'each item on the rail and photographs what is on screen. A job '
            'takes them again whenever Studio changes, so a section added this '
            'week is a section you can see this week.'),
        StudioSectionGallery(),
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
