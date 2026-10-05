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
          'Build pages visually, design data models and edit their records '
              'without writing an admin panel.',
          'Frontend and backend functions built from steps are free too. '
              'Studio Pro comes with Dartvel Cloud, and adds Figma import, '
              'reusable components, revision history and team review.',
        ]),
        StudioShot(
          'assets/studio_shots/page-builder.png',
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
          '# open https://your-host/__studio and sign in there',
        ]),
        Bullets(<String>[
          'Only people you grant can open it. Studio has its own sign-in at '
              '/__studio/login, so it opens even with your app\'s account '
              'pages turned off.',
          'Design a data model in the browser, with field types, rules, '
              'relations, indexes and who may read and write it, and edit its '
              'records in a form. An edit made against a row that changed after '
              'you opened it is refused.',
          'Studio fits a phone: sections move to a bar along the bottom, and '
              'the editor shows Elements, Page or Style one at a time.',
        ]),
        StudioShot(
          'assets/studio_shots/model-records.png',
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
          'Set padding and margin uniformly or on each edge; saved pages and '
              'exported Dart retain the spacing. Compact spacing fields '
              'announce their full names to screen readers.',
          'Deploy sends the page to your website, phone and tablet apps, '
              'desktop apps, TVs, browser extensions and devices, or only the '
              'ones you tick.',
        ]),
        StudioShot(
          'assets/studio_shots/deploy-menu.png',
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
      children: <Widget>[
        Eyebrow('FORMULA BAR AND COMMAND PALETTE'),
        Heading('Edit what is selected in one line, and reach anything with Ctrl+K.'),
        Bullets(<String>[
          'The formula bar runs across the top of the editor, as in Excel or '
              'Power Apps. Select an element and its text is there; the box on '
              'the left picks any other field: its layout, its style, its '
              'action.',
          'A formula is a value of that field\'s kind: "text", 12 * 2 + 4, '
              '#111827 or rgb(17, 24, 39), one of a choice\'s options, TRUE, '
              'or Navigate("/pricing"). It is highlighted as you type and '
              'offers completions: options, routes, data models and their '
              'fields, functions. Enter applies it, Esc puts back what was '
              'there, and a formula that is wrong says where and writes '
              'nothing. Each edit is one step in the canvas\'s undo history.',
          'Ctrl+K (Cmd+K on a Mac) opens the command palette: every section, '
              'every page, every element on the page by name, and what can be '
              'done to it, found by typing a few letters. Ctrl+D duplicates '
              'the selected element, and Ctrl+/ lists every shortcut.',
        ]),
        StudioShot(
          'assets/studio_shots/formula-bar.png',
          'The Studio page editor with the formula bar across the top: the '
              'fontSize field picked in the name box and 12 * 3 + 12 being '
              'typed for the selected heading',
          caption: 'The formula bar: fontSize picked in the name box, and a '
              'formula typed for the selected heading.',
        ),
        StudioShot(
          'assets/studio_shots/command-palette.png',
          'The Studio command palette open over the editor, filtered to '
              'insert commands',
          caption: 'Ctrl+K: three letters narrow it to what can be inserted.',
        ),
      ],
    ),
    Section(
      tint: true,
      children: <Widget>[
        Bullets(<String>[
          'Studio inherits your app’s Material theme. New projects start with '
          'Dartvel’s light and dark theme. Custom Studio colors and the visible '
          'server-rendered first frame are still being brought into parity.',
        ]),
        Eyebrow('KEYBOARD AND SCREEN READER'),
        Heading('Every control is a control, not a picture of one.'),
        Bullets(<String>[
          'On sign-in, the email and password fields have accessible labels. '
              'Tab from the password reaches Sign in; Enter submits it.',
          'Tab reaches every button, every icon on the rail and the toolbar, '
              'and every toggle. Enter and Space both press one. The focus is '
              'drawn as a ring on the control itself, so you can see where you '
              'are.',
          'A screen reader is told what each control is, what it is called and '
              'whether it works. A control with nothing to do — Undo with no '
              'history, Sign in while signing in — says so and is skipped, '
              'rather than looking live and doing nothing.',
          'Ctrl+F works on a Studio screen, because Studio is a route of your '
              'app rendered by the same server as every other page. So does '
              'selecting text with the mouse, the arrow keys, a remote\'s '
              'D-pad and switch control.',
          'Each screen has its own address — /__studio is Pages, /__studio/'
              'components is Components, /__studio/data/Product is one model '
              'and /__studio/data/Product/p-1 opens one record — '
              'so a screen can be linked, bookmarked and reloaded, and the '
              'server sends a document with it for anything reading without '
              'the app.',
        ]),
      ],
    ),
    Section(
      children: <Widget>[
        Eyebrow('IN THE FREE STUDIO'),
        Heading('Records, routes and review in the same place as your pages.'),
        DVBox.wrapLine(<Widget>[
          SiteCard(
            'Pages',
            'Every page, the ones in your code included. Insert, Layers, the '
                'inspector, undo and redo, deploy, restore and code export.',
            section: 'Dartvel Studio',
          ),
          SiteCard(
            'Components',
            'Make a card, a header or a price box once and put it on any '
                'page. Each use sets its own text, picture, colour and tap; '
                'change the component and every page changes. Ctrl+Alt+K '
                'turns a selection into one.',
            section: 'Dartvel Studio',
          ),
          SiteCard(
            'Data',
            'Design data models, and browse and edit each model\'s records. '
                'Sensitive fields can be set there but never read back.',
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
            'Keyboard shortcuts',
            'Keys that open a page of your app from anywhere in it, set '
                'without code; press ? in the app to see them.',
            section: 'Dartvel Studio',
          ),
          SiteCard(
            'GitHub',
            'See what Studio changed as a diff, then open a pull request or '
                'push, so the next release is built with it. During `dartvel '
                'dev` Studio writes straight to your project\'s files.',
            section: 'Dartvel Studio',
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
            '`dartvel docs` builds a Flutter site of your models, functions, '
                'routes, jobs and policies. It is off unless dartvel.docs '
                'turns it on, and served behind Studio by default.',
            section: 'Documentation Generation',
          ),
          SiteCard(
            'Model pages',
            'Every data model gives each record a public page with head '
                'tags and structured data, unless it opts out. A row\'s featured '
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
          'assets/studio_shots/frontend-function.png',
          'The Frontend section of Studio with the orderAhead function open: '
              'Call, Condition and Return steps on the canvas, and the '
              'selected Condition step\'s argument on the right',
          caption: 'A frontend function: what a button does, built from '
              'steps that branch on a value.',
        ),
        StudioShot(
          'assets/studio_shots/backend-function.png',
          'The Backend section with the placeOrder function open and a Call '
              'step selected, and the '
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
