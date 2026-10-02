// Documentation Generation: the site is a second rendering of the project
// graph, not a second copy of it maintained by hand.
//
// What these guard is the failure a generated site can actually have. It
// cannot be out of date with the code, so it fails by being plausible and
// wrong: a sensitive field rendered like any other, a decision pointing at a
// function that was renamed, a node the AI context knows about that the site
// silently leaves out, or bytes that change between two builds of one input.
//
// It used to guard those by matching HTML. The site is an application now --
// `dartvel docs` compiles `DVDocsApp` and hands it the document these tests
// read -- so what is asserted here is the document: the content, and the
// targets a link names. A test that matched markup would keep passing after
// the markup was gone, which is how a page stops being checked and starts
// only being built.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/docs/docs_site.dart';
import 'package:dartvel_cli/src/generators/policy_classes.dart';
import 'package:dartvel_cli/src/graph/project_graph.dart';
import 'package:dartvel_cli/src/mcp/framework_mcp_server.dart';
import 'package:dartvel_core/dartvel.dart' show DVDiagnostics, DVDiagnostic;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const Map<String, String> _project = <String, String>{
  'pubspec.yaml': '''
name: docs_probe
publish_to: none
environment:
  sdk: ^3.9.0
dartvel:
  modules:
    store:
      mount: /store
      source:
        path: modules/store
''',
  'modules/store/pubspec.yaml': '''
name: store
publish_to: none
dartvel:
  module:
    name: Store
''',
  'modules/store/lib/pages/index.page.dart': '''
import 'package:flutter/widgets.dart';

/// The shop window.
@DVPage(title: 'Store')
Widget _storeHomePage(BuildContext context) => const SizedBox();
''',
  'lib/models/user.dart': '''
import 'package:dartvel_core/dartvel.dart';

/// A person who can sign in.
@DVModel(generatePublicPages: true)
class _User {
  final String id;

  /// Where receipts are sent.
  final String email;

  /// The number on their tax return.
  @DVModel.searchableField()
  @DVModel.sensitiveField(encrypted: true)
  final String taxId;

  final int seats;

  const _User({
    required this.id,
    required this.email,
    required this.taxId,
    required this.seats,
  });
}

// Seed data kept beside the model. A documentation site that printed an
// example row from it would be the leak the annotation exists to prevent.
const Map<String, Object?> seedUser = <String, Object?>{
  'email': 'ada@example.com',
  'taxId': '078-05-1120',
};
''',
  'lib/models/order.dart': '''
import 'package:dartvel_core/dartvel.dart';

/// A paid basket.
@DVModel(generatePublicPages: false)
class _Order {
  final String id;

  /// Who paid.
  final User buyer;

  @DVModel.sensitiveField()
  @DVModel.searchableField()
  final String bankAccount;

  const _Order({required this.id, required this.buyer, required this.bankAccount});
}
''',
  'lib/policies/user_policy.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVPolicy(User)
class UserPolicy {
  bool view(User? user, User resource) => user != null;
  bool update(User? user, User resource) => user?.id == resource.id;
}
''',
  'lib/pages/index.page.dart': '''
import 'package:flutter/widgets.dart';

/// The front door. <script>alert(1)</script>
@DVPage(title: 'Home')
Widget _indexPage(BuildContext context) => const SizedBox();
''',
  'lib/pages/admin.page.dart': '''
import 'package:flutter/widgets.dart';

@DVPage(policy: DVPolicies.viewAdmin)
Widget _adminPage(BuildContext context) => const SizedBox();
''',
  'lib/backend/functions/checkout.post.dart': '''
import 'package:dartvel_core/dartvel.dart';

/// Charges the basket and returns the order id.
@DVBackendFunction(policy: DVPolicies.checkout)
@DVUseMiddleware([DVMiddlewares.tracing, DVMiddlewares.rateLimit])
Future<String> _checkout(DVContext context, String basketId) async =>
    basketId;
''',
  'lib/backend/functions/sum.post.dart': '''
/// Adds two numbers.
int sum(int a, int b) => a + b;
''',
  'lib/backend/functions/health.get.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _health() async => <String, Object?>{};
''',
  'lib/jobs/welcome.dart': '''
import 'package:dartvel_core/dartvel.dart';

/// Sends the welcome email.
@DVJob(queue: 'mail')
class _SendWelcome {
  final String userId;

  const _SendWelcome({required this.userId});
}
''',
  'lib/schedules.dart': '''
import 'package:dartvel_core/dartvel.dart';

/// Totals the day.
@DVBackendCron('0 3 * * *')
Future<void> nightlyReport() async {}

@DVClientCron('*/5 * * * *')
void refreshDashboard() {}
''',
  'docs/decisions/0001-checkout.md': '''
# 1. Checkout charges before it writes the order

The `function:checkout` function charges first, and the `model:Order` row is
written after it succeeds. It used to call `function:legacyCharge`.

A plain code span such as `http://example.com` or `a:b` names nothing.
''',
};

Directory _write(Map<String, String> files, {String prefix = 'dv_docs_'}) {
  final Directory root = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  files.forEach((String relative, String contents) {
    final File file = File(
      p.joinAll(<String>[root.path, ...relative.split('/')]),
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  });
  return root;
}

Future<DVDocsSite> _siteFor(Map<String, String> files) =>
    DVDocsSite.build(root: _write(files).path);

/// Every text a block holds, joined, whatever kind of block it is.
///
/// The stand-in for the old `contains('...')` against markup: a test that
/// cares that a fact is on the page should not have to care which block
/// carries it, and a page that moved a sentence from a paragraph into a
/// table cell has not changed.
String _text(List<DVDocsBlock> blocks) => blocks
    .map((DVDocsBlock block) => switch (block) {
          final DVDocsParagraph p => _spans(p.spans),
          final DVDocsHeading h => _spans(h.spans),
          final DVDocsList l => l.items
              .map((DVDocsListItem i) => _spans(i.spans))
              .join(' '),
          final DVDocsCode c => c.text,
          final DVDocsTable t => <String>[
            ...t.columns.map((DVDocsColumn c) => c.label),
            for (final DVDocsRow row in t.rows)
              row.cells.map(_spans).join(' '),
          ].join(' '),
        })
    .join('\n');

String _spans(List<DVDocsSpan> spans) =>
    spans.map((DVDocsSpan s) => s.text).join();

/// The blocks from the block anchored [anchor] to the end of its section.
List<DVDocsBlock> _section(DVDocsPage page, String anchor) {
  final List<DVDocsBlock>? section = page.section(anchor);
  expect(
    section,
    isNotNull,
    reason: 'nothing on ${page.id} is anchored $anchor',
  );
  return section!;
}

DVDocsTable _table(DVDocsPage page, String anchor) {
  final List<DVDocsBlock> section = _section(page, anchor);
  final Iterable<DVDocsTable> tables = section.whereType<DVDocsTable>();
  expect(tables, hasLength(1), reason: 'no table under $anchor on ${page.id}');
  return tables.single;
}

/// The one table on [page] carrying a row with [rowId]. For the pages whose
/// tables are per-section and have no anchor of their own.
DVDocsTable _tableWithRow(DVDocsPage page, String rowId) {
  final Iterable<DVDocsTable> tables = page.blocks.whereType<DVDocsTable>().where(
        (DVDocsTable t) => t.rows.any((DVDocsRow r) => r.id == rowId),
      );
  expect(tables, hasLength(1), reason: 'no table with a $rowId row');
  return tables.single;
}

/// The text of one cell, found by the ids the row and the column carry.
String _cell(DVDocsTable table, String rowId, String columnId) {
  final int column = table.columns.indexWhere(
    (DVDocsColumn c) => c.id == columnId,
  );
  expect(column, isNot(-1), reason: 'no column $columnId');
  final Iterable<DVDocsRow> rows =
      table.rows.where((DVDocsRow r) => r.id == rowId);
  expect(rows, hasLength(1), reason: 'no row $rowId');
  return _spans(rows.single.cells[column]);
}

/// The kind of every span in the document, for the schema test.
Iterable<String> _spanKinds(DVDocsDocument document) => <String>[
      for (final DVDocsPage page in document.pages)
        for (final DVDocsBlock block in page.blocks)
          ...switch (block) {
            final DVDocsParagraph p => p.spans,
            final DVDocsHeading h => h.spans,
            final DVDocsList l => <List<DVDocsSpan>>[
                for (final DVDocsListItem i in l.items) i.spans,
              ].expand((List<DVDocsSpan> s) => s),
            final DVDocsCode _ => const <DVDocsSpan>[],
            final DVDocsTable t => <List<DVDocsSpan>>[
                for (final DVDocsRow row in t.rows) ...row.cells,
              ].expand((List<DVDocsSpan> s) => s),
          }.map((DVDocsSpan s) => s.kind),
    ];

void main() {
  group('the document', () {
    test('is data, and names the pages the app routes', () async {
      final DVDocsSite site = await _siteFor(_project);
      final DVDocsDocument document = site.document;

      // The site was nine hand-written pages. It is one document now, and the
      // application renders every page from it -- so the set of pages is a
      // fact the app reads rather than one the two sides each hold.
      expect(document.application, 'docs_probe');
      expect(document.navigation, <(String, String)>[
        ('index', 'Overview'),
        ('models', 'Models'),
        ('functions', 'Functions'),
        ('routes', 'Routes'),
        ('jobs', 'Jobs and cron'),
        ('policies', 'Policies'),
        ('modules', 'Modules'),
        ('diagnostics', 'Diagnostics'),
      ]);
      expect(
        document.pages.map((DVDocsPage p) => p.id),
        containsAll(<String>[
          'index',
          'models',
          'functions',
          'routes',
          'jobs',
          'policies',
          'modules',
          'diagnostics',
          'decision:0001-checkout',
        ]),
      );
      // Every page the navigation names exists, and every page is reachable
      // from somewhere: a page nothing links to is a page nobody finds.
      for (final (String id, String _) in document.navigation) {
        expect(document.page(id), isNotNull, reason: id);
      }
      final Set<String> named = <String>{
        for (final (String id, String _) in document.navigation) id,
        ...document.pages
            .where((DVDocsPage p) => p.id.startsWith('decision:'))
            .map((DVDocsPage p) => p.id),
      };
      expect(
        document.pages.map((DVDocsPage p) => p.id).toSet(),
        named,
        reason: 'a page the navigation does not reach',
      );
    });

    test('survives being written and read back unchanged', () async {
      // The application is a separate package that cannot import the CLI, so
      // this document crosses a process boundary as bytes. A span whose text
      // did not come back identical would be a page that renders differently
      // from the one the build checked.
      final DVDocsSite site = await _siteFor(_project);
      final String written = site.file(dvDocsPayloadFile);
      final DVDocsDocument read = DVDocsDocument.fromJson(
        jsonDecode(written)! as Map<String, Object?>,
      );

      expect(read.toJson(), site.document.toJson());
      expect(read.application, 'docs_probe');
      expect(read.pages, hasLength(site.document.pages.length));
    });

    test('every span is one of the kinds the app knows how to draw', () async {
      // The app is the only thing that can misinterpret this document, and it
      // misinterprets by meeting a kind it does not know. That is the whole
      // attack surface of a payload written by a build step, so it is
      // enumerated here rather than trusted.
      final DVDocsSite site = await _siteFor(_project);
      final Set<String> kinds = _spanKinds(site.document).toSet();

      expect(kinds, isNotEmpty);
      expect(
        kinds.difference(<String>{
          'text',
          'code',
          'strong',
          'link',
          'badge',
          'denied',
          'gone',
          'note',
          'finding',
        }),
        isEmpty,
      );
    });

    test('carries no markup of its own', () async {
      // The site was hand-written HTML with a stylesheet the application's
      // theme never touched. What the build writes now is a document the
      // application draws, and the strongest statement that can be made
      // about it is that there is nothing in it for a browser to parse.
      //
      // Checked against a project with no doc comment anywhere, because a
      // doc comment is a sentence somebody wrote: one of them may say
      // `<script>`, and that is data (see the doc comment test below), not
      // the build emitting markup.
      final DVDocsSite site = await _siteFor(<String, String>{
        'pubspec.yaml': 'name: bare\n',
      });
      final String written = site.file(dvDocsPayloadFile);

      expect(jsonDecode(written), isA<Map<String, Object?>>());
      for (final String markup in <String>[
        '<!doctype',
        '<html',
        '<body',
        '<script',
        '<style',
        '<div',
        '<a href',
        'onclick=',
      ]) {
        expect(written, isNot(contains(markup)), reason: markup);
      }
    });
  });

  group('models', () {
    test(
      'every model and field is rendered with its type and doc comment',
      () async {
        final DVDocsSite site = await _siteFor(_project);
        final DVDocsPage models = site.document.page('models')!;
        final String user = _text(_section(models, 'model-User'));
        expect(user, contains('A person who can sign in.'));
        expect(_text(_section(models, 'model-Order')), contains('Who paid.'));

        final DVDocsTable fields = _table(models, 'model-User');
        expect(
          fields.rows.map((DVDocsRow r) => r.id),
          containsAll(<String>[
            'field-User-id',
            'field-User-email',
            'field-User-taxId',
            'field-User-seats',
          ]),
        );
        expect(
          _cell(fields, 'field-User-email', 'description'),
          contains('Where receipts are sent.'),
        );
        expect(
          _cell(fields, 'field-User-email', 'type'),
          contains('String'),
        );
        // The source the description was read from, so a reader who disputes
        // it can go and look.
        expect(user, contains('lib/models/user.dart:4'));
      },
    );

    test('a sensitive field is named and never valued', () async {
      final DVDocsSite site = await _siteFor(_project);
      final DVDocsPage models = site.document.page('models')!;
      final String page = _text(models.blocks);

      // Both annotation orders, and the form with arguments. A field the
      // graph failed to mark would render as an ordinary field, with an
      // example value, and look entirely correct.
      for (final String id in <String>[
        'field-User-taxId',
        'field-Order-bankAccount',
      ]) {
        final DVDocsRow row = _tableWithRow(models, id).rows.firstWhere(
          (DVDocsRow r) => r.id == id,
        );
        expect(
          row.cells.expand((List<DVDocsSpan> cell) => <String>[_spans(cell)]),
          contains('sensitive'),
          reason: '$id is not marked',
        );
      }
      expect(page, contains('"taxId": "[sensitive]"'));
      expect(page, contains('"email": "text"'));

      for (final MapEntry<String, String> file in site.files.entries) {
        expect(file.value, isNot(contains('078-05-1120')), reason: file.key);
        expect(
          file.value,
          isNot(contains('ada@example.com')),
          reason: file.key,
        );
      }
    });

    test(
      'the graph the site publishes marks the sensitive field too',
      () async {
        final DVDocsSite site = await _siteFor(_project);
        final Map<String, Object?> graph =
            jsonDecode(site.file(dvDocsGraphFile))! as Map<String, Object?>;
        final List<Object?> models = graph['models']! as List<Object?>;
        Map<String, Object?> field(String model, String name) {
          final Map<String, Object?> m = models
              .cast<Map<String, Object?>>()
              .firstWhere((Map<String, Object?> m) => m['name'] == model);
          return (m['fields']! as List<Object?>)
              .cast<Map<String, Object?>>()
              .firstWhere((Map<String, Object?> f) => f['name'] == name);
        }

        expect(field('User', 'taxId')['sensitive'], isTrue);
        expect(field('Order', 'bankAccount')['sensitive'], isTrue);
        expect(field('User', 'email').containsKey('sensitive'), isFalse);
      },
    );

    test('a field typed as another model is a relation to it', () async {
      final DVDocsSite site = await _siteFor(_project);
      final DVDocsPage models = site.document.page('models')!;
      final List<DVDocsBlock> order = _section(models, 'model-Order');

      // The relation itself, and it as a target rather than as text: the
      // field's type cell links there too, and asserting on the text alone
      // would pass with no relations rendered at all.
      final Iterable<DVDocsList> lists = order.whereType<DVDocsList>();
      final Iterable<DVDocsListItem> relations = lists
          .expand((DVDocsList l) => l.items)
          .where((DVDocsListItem i) => i.spans.first.text == 'buyer');
      expect(relations, hasLength(1));
      expect(
        relations.single.spans
            .where((DVDocsSpan s) => s.target?.page == 'models')
            .map((DVDocsSpan s) => s.text),
        <String>['User'],
      );
    });

    test('policies and generated surfaces are listed on the model', () async {
      final DVDocsSite site = await _siteFor(_project);
      final DVDocsPage models = site.document.page('models')!;
      final String user = _text(_section(models, 'model-User'));
      expect(user, contains('UserPolicy'));
      expect(user, contains('User.Form'));
      expect(user, contains('User.Page'));
      expect(user, contains('/users/:id'));
      // Every model gets the page component; one that opted out of public
      // pages has no route. Claiming one for Order would be a link to a 404.
      expect(_text(_section(models, 'model-Order')), contains('Order.Page'));
      expect(
        _text(_section(models, 'model-Order')),
        isNot(contains('/orders/:id')),
      );
    });

    test('a doc comment is data, not something to interpret', () async {
      final DVDocsSite site = await _siteFor(_project);
      final String routes = site.file(dvDocsPayloadFile);

      // The site mounted inside the application, on the application's own
      // origin, and a doc comment is written by whoever wrote the page. A
      // comment carrying a script ran with the reader's session when the site
      // was HTML; as a span it is a sentence, and the bytes say so.
      expect(routes, contains('<script>alert(1)</script>'));
      final DVDocsPage page = site.document.page('routes')!;
      expect(
        _text(_section(page, 'route-/')),
        contains('The front door. <script>alert(1)</script>'),
      );
    });
  });

  group('functions', () {
    test('a function carries its signature, doc comment and source', () async {
      final DVDocsSite site = await _siteFor(_project);
      final List<DVDocsBlock> checkout = _section(
        site.document.page('functions')!,
        'function-checkout',
      );
      final String text = _text(checkout);
      expect(text, contains('POST'));
      expect(text, contains('/checkout'));
      expect(
        text,
        contains('Future<String> checkout(DVContext context, String basketId)'),
      );
      expect(text, contains('Charges the basket and returns the order id.'));
      expect(text, contains('lib/backend/functions/checkout.post.dart:4'));
      // The signature is a code block, not a paragraph: the app draws it as
      // one, and a test that only checked the text would not notice it being
      // flattened into a sentence.
      expect(
        checkout.whereType<DVDocsCode>().map((DVDocsCode c) => c.text),
        contains(
          'Future<String> checkout(DVContext context, String basketId)',
        ),
      );
    });

    test(
      'an unannotated function is still typed, with its signature and doc',
      () async {
        // Most functions in the repository's own example carry no annotation.
        // The generator types them by signature, so the site does too.
        final List<DVDocsBlock> sum = _section(
          (await _siteFor(_project)).document.page('functions')!,
          'function-sum',
        );
        expect(_text(sum), contains('int sum(int a, int b)'));
        expect(_text(sum), contains('Adds two numbers.'));
        expect(
          sum.whereType<DVDocsList>().single.items
              .map((DVDocsListItem i) => i.id)
              .toList(),
          contains('csrf'),
        );
      },
    );

    test(
      'the request lifecycle stages are listed in the order they run',
      () async {
        final DVDocsPage functions = (await _siteFor(_project))
            .document
            .page('functions')!;
        List<String?> stages(String anchor) => _section(
          functions,
          anchor,
        ).whereType<DVDocsList>().single.items
            .map((DVDocsListItem i) => i.id)
            .toList();

        expect(stages('function-checkout'), <String>[
          'tenant',
          // Sec-GPC is read for every request, so the scope it opens is a
          // stage of the lifecycle and belongs in the list that documents
          // it. It sits above tracing because the denial is in force for
          // everything below, the span included.
          'privacy',
          'tracing',
          'middleware:rateLimit',
          'body',
          'csrf',
          'policy',
          'context',
          'function',
        ]);

        // A GET never has its body read, so listing that stage would describe
        // a step this request does not take.
        expect(stages('function-health'), <String>[
          'tenant',
          'privacy',
          'csrf',
          'function',
        ]);
      },
    );
  });

  group('routes', () {
    test('pages, generated model pages and mounted module routes', () async {
      final DVDocsPage routes = (await _siteFor(_project))
          .document
          .page('routes')!;
      expect(_text(_section(routes, 'route-/')), contains('The front door.'));
      expect(
        _text(_section(routes, 'route-/admin')),
        contains('DVPolicies.viewAdmin'),
      );
      // The link a generated model page carries names the model it came from,
      // as a target: a page id and an anchor, which the app turns into a
      // route. An href string would break the moment a page moved.
      final Iterable<DVDocsSpan> toModel = _section(
        routes,
        'route-/users/:id',
      ).whereType<DVDocsParagraph>().expand((DVDocsParagraph p) => p.spans)
          .where((DVDocsSpan s) => s.target?.anchor == 'model-User');
      expect(toModel, isNotEmpty);
      expect(toModel.first.target!.page, 'models');

      final String store = _text(_section(routes, 'route-/store'));
      expect(store, contains('store'));
      expect(store, contains('modules/store/lib/pages/index.page.dart:4'));
      expect(store, contains('The shop window.'));
    });
  });

  group('jobs and schedules', () {
    test(
      'jobs with their queue, and cron with its expression and target',
      () async {
        final DVDocsPage jobs = (await _siteFor(_project))
            .document
            .page('jobs')!;
        final String welcome = _text(_section(jobs, 'job-SendWelcome'));
        expect(welcome, contains('mail'));
        expect(welcome, contains('Sends the welcome email.'));

        final String nightly = _text(_section(jobs, 'schedule-nightlyReport'));
        expect(nightly, contains('0 3 * * *'));
        expect(nightly, contains('backend'));
        expect(nightly, contains('Totals the day.'));

        // A client schedule is a request, not a guarantee, and a reference
        // that printed it beside the server's as if the two were the same
        // clock would be the implied promise the specification refuses.
        final String client = _text(_section(jobs, 'schedule-refreshDashboard'));
        expect(client, contains('*/5 * * * *'));
        expect(client, contains('client'));
        expect(client, contains('not a guarantee'));
        expect(nightly, isNot(contains('not a guarantee')));
      },
    );
  });

  group('policy matrix', () {
    test('each resource against each action, and what each guards', () async {
      final DVDocsPage policies = (await _siteFor(_project))
          .document
          .page('policies')!;
      final DVDocsTable matrix = _table(policies, 'policy-User');
      // Every action a policy can answer, as a column. The matrix used to be
      // a fixed five; the actions a runtime refuses are nine more, and a
      // column that is missing is a column that reads as denied by omission
      // rather than by decision.
      expect(matrix.columns.map((DVDocsColumn c) => c.id), <String>[
        'policy',
        ...dvPolicyActions,
      ]);

      final String rowId = matrix.rows.first.id!;
      expect(_cell(matrix, rowId, 'view'), contains('UserPolicy.view'));
      expect(_cell(matrix, rowId, 'update'), contains('UserPolicy.update'));
      // Default-deny is what the runtime does for an action nobody wrote, and
      // the cell says so in its own voice rather than being left blank: a
      // blank cell reads as a value the build could not find.
      expect(_cell(matrix, rowId, 'delete'), 'denied');

      final String guarded = _text(_section(policies, 'guarded'));
      expect(guarded, contains('DVPolicies.viewAdmin'));
      expect(guarded, contains('/admin'));
      expect(guarded, contains('DVPolicies.checkout'));
      expect(guarded, contains('POST /checkout'));
    });
  });

  group('module map', () {
    test(
      'each module with its mount, deployment and what it was granted',
      () async {
        final String store = _text(
          _section(
            (await _siteFor(_project)).document.page('modules')!,
            'module-store',
          ),
        );
        expect(store, contains('/store'));
        expect(store, contains('embedded'));
        expect(store, contains('data="shared"'));
        expect(store, contains('auth="inherit"'));
      },
    );

    // The map showed what a module was declared to need, and nothing about
    // whether it gets it: a reader could not tell a module the parent had
    // granted from one the build would refuse.
    Map<String, String> granted({required String egress}) => <String, String>{
      'pubspec.yaml': '''
name: shop
dartvel:
  modules:
    store:
      mount: /store
      source:
        path: modules/store
      grant:
        secrets: [STORE_KEY]
        egress: [$egress]
''',
      'modules/store/pubspec.yaml': '''
name: store
version: 1.0.0
dartvel:
  module:
    capabilities:
      secrets: [STORE_KEY]
      egress: ['api.example.com']
''',
      'modules/store/lib/pay.dart': '''
Future<void> pay() async {
  final String key = DV.Secrets.get('STORE_KEY');
  await DV.Http.post('https://api.example.com/charge', json: {'k': key});
}
''',
    };

    test('shows the grant, and what the trust evaluation says of it', () async {
      final String store = _text(
        _section(
          (await _siteFor(granted(egress: "'stripe.com'")))
              .document
              .page('modules')!,
          'module-store',
        ),
      );
      expect(store, contains('Grant'));
      expect(store, contains('secrets: STORE_KEY'));
      expect(store, contains('Trust'));
      expect(store, contains('DV-MODULE-001'));
      expect(store, contains('api.example.com'));
    });

    test('says so when there is nothing to refuse', () async {
      final String store = _text(
        _section(
          (await _siteFor(granted(egress: "'api.example.com'")))
              .document
              .page('modules')!,
          'module-store',
        ),
      );
      expect(store, contains('Trust'));
      expect(store, isNot(contains('DV-MODULE-00')));
      expect(store, contains('uses only what it is granted'));
    });
  });

  group('a project with nothing under lib', () {
    test('still builds its documentation', () async {
      // Static-path discovery answers a constant empty list when there is no
      // lib directory, and the site sorted it in place, so `dartvel docs`
      // threw on a project that had not written any code yet.
      final DVDocsSite site = await _siteFor(<String, String>{
        'pubspec.yaml': 'name: empty\n',
      });
      expect(site.document.page('modules'), isNotNull);
      expect(site.document.page('models')!.blocks, isNotEmpty);
    });
  });

  group('diagnostics glossary', () {
    test('every registered code, from the registry explain reads', () async {
      final DVDocsPage glossary = (await _siteFor(_project))
          .document
          .page('diagnostics')!;
      final List<String> codes = <String>[
        for (final DVDocsBlock block in glossary.blocks)
          if (block is DVDocsTable)
            for (final DVDocsRow row in block.rows)
              if (row.id != null) row.id!,
      ];

      for (final DVDiagnostic d in DVDiagnostics.all) {
        expect(codes, contains(d.code), reason: d.code);
      }
      expect(codes, hasLength(DVDiagnostics.all.length));
    });
  });

  group('decision records', () {
    test(
      'a decision links to the nodes it names, and they link back',
      () async {
        final DVDocsSite site = await _siteFor(_project);
        final DVDocsPage decision =
            site.document.page('decision:0001-checkout')!;
        expect(_text(decision.blocks), contains('1. Checkout charges before it writes the order'));

        // Both directions, as targets rather than as hrefs: a link the app
        // follows has to name a page the app routes.
        final Set<String> named = decision.blocks
            .whereType<DVDocsParagraph>()
            .expand((DVDocsParagraph p) => p.spans)
            .where(
              (DVDocsSpan s) =>
                  s.target?.anchor?.startsWith('function-') == true ||
                  s.target?.anchor?.startsWith('model-') == true,
            )
            .map((DVDocsSpan s) => '${s.target!.page}#${s.target!.anchor}')
            .toSet();
        expect(
          named,
          <String>{'functions#function-checkout', 'models#model-Order'},
        );

        // And back. A decision nobody can reach from the node it explains is
        // a decision that is not documentation of anything.
        for (final (String page, String anchor) in <(String, String)>[
          ('functions', 'function-checkout'),
          ('models', 'model-Order'),
        ]) {
          final List<DVDocsSpan> links = _section(
            site.document.page(page)!,
            anchor,
          ).whereType<DVDocsParagraph>().expand((DVDocsParagraph p) => p.spans)
              .where(
                (DVDocsSpan s) =>
                    s.target?.page == 'decision:0001-checkout',
              )
              .toList();
          expect(links, isNotEmpty, reason: '$page#$anchor');
        }
      },
    );

    test(
      'DV-DOCS-001: a decision naming a node that no longer exists',
      () async {
        final DVDocsSite site = await _siteFor(_project);
        final List<DVDocsFinding> gone = site.findings
            .where((DVDocsFinding f) => f.code == 'DV-DOCS-001')
            .toList();
        expect(gone, hasLength(1));
        expect(gone.single.source, 'docs/decisions/0001-checkout.md:4');
        expect(gone.single.message, contains('function:legacyCharge'));

        // Named, marked as gone, and linked to nothing. A link to a target
        // that is not in the document is a 404 in a page whose whole job is
        // to be right about what exists.
        final Iterable<DVDocsSpan> spans = _section(
          site.document.page('decision:0001-checkout')!,
          '0001-checkout',
        ).whereType<DVDocsParagraph>().expand((DVDocsParagraph p) => p.spans);
        final DVDocsSpan legacy = spans.firstWhere(
          (DVDocsSpan s) => s.text == 'function:legacyCharge',
        );
        expect(legacy.kind, 'gone');
        expect(legacy.target, isNull);
      },
    );

    test('the reference comes back when the node does', () async {
      final Map<String, String> files = Map<String, String>.of(_project)
        ..['lib/backend/functions/legacy_charge.post.dart'] = '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<void> _legacyCharge() async {}
''';
      final DVDocsSite site = await _siteFor(files);
      expect(
        site.findings.where((DVDocsFinding f) => f.code == 'DV-DOCS-001'),
        isEmpty,
      );
    });
  });

  group('DV-DOCS-002', () {
    test('a node whose source mapping no longer resolves is reported, and '
        'rendered without an invented description', () async {
      final Directory root = _write(_project);
      final DartvelProjectGraph real = await DartvelProjectGraph.build(
        root: root.path,
        pkgName: 'docs_probe',
      );
      final DartvelProjectGraph stale = DartvelProjectGraph(
        models: real.models,
        routes: real.routes,
        jobs: real.jobs,
        functions: <DVGraphFunction>[
          ...real.functions,
          const DVGraphFunction(
            name: 'refund',
            method: 'POST',
            path: '/refund',
            source: 'lib/backend/functions/refund.post.dart:3',
          ),
        ],
      );
      // And one whose file is there but whose line does not hold the
      // declaration: the file was edited after the mapping was taken.
      final DVGraphModel user = real.models.firstWhere(
        (DVGraphModel m) => m.name == 'User',
      );
      final DartvelProjectGraph moved = DartvelProjectGraph(
        models: <DVGraphModel>[
          for (final DVGraphModel m in real.models)
            if (m.name == 'User')
              DVGraphModel(
                name: 'User',
                source: 'lib/models/user.dart:1',
                fields: user.fields,
              )
            else
              m,
        ],
        routes: stale.routes,
        jobs: stale.jobs,
        functions: stale.functions,
      );

      final DVDocsSite site = await DVDocsSite.build(
        root: root.path,
        graph: moved,
      );
      final List<DVDocsFinding> unmapped = site.findings
          .where((DVDocsFinding f) => f.code == 'DV-DOCS-002')
          .toList();
      expect(unmapped.map((DVDocsFinding f) => f.source), <String>[
        'lib/backend/functions/refund.post.dart:3',
        'lib/models/user.dart:1',
      ]);

      // Said, not invented around. A node the build cannot read still appears
      // in the page with its path on it, because a reference that has
      // silently vanished is harder to notice than one that admits itself.
      expect(
        _text(
          _section(
            site.document.page('functions')!,
            'function-refund',
          ),
        ),
        contains('no source to render from'),
      );
      expect(
        _text(_section(site.document.page('models')!, 'model-User')),
        isNot(contains('A person who can sign in.')),
      );
    });

    test('a project whose mappings all resolve reports none', () async {
      final DVDocsSite site = await _siteFor(_project);
      expect(
        site.findings.where((DVDocsFinding f) => f.code == 'DV-DOCS-002'),
        isEmpty,
      );
    });
  });

  group('one body of data, two readers', () {
    test(
      'the site publishes exactly the graph the AI context is given',
      () async {
        final Directory root = _write(_project);
        final DVDocsSite site = await DVDocsSite.build(root: root.path);
        final Map<String, Object?>? reply =
            await DartvelFrameworkMcpServer(root: root.path).handle(
              <String, Object?>{
                'jsonrpc': '2.0',
                'id': 1,
                'method': 'tools/call',
                'params': <String, Object?>{
                  'name': 'dartvel_inspect_graph',
                  'arguments': <String, Object?>{},
                },
              },
            );
        final Map<String, Object?> result =
            reply!['result']! as Map<String, Object?>;
        final String text =
            ((result['content']! as List<Object?>).single
                    as Map<String, Object?>)['text']!
                as String;
        expect(site.file(dvDocsGraphFile), '$text\n');
      },
    );

    test('every node in that graph has a place in the document', () async {
      final DVDocsSite site = await _siteFor(_project);
      final Map<String, Object?> graph =
          jsonDecode(site.file(dvDocsGraphFile))! as Map<String, Object?>;
      final Set<String> anchors = <String>{
        for (final DVDocsPage page in site.document.pages)
          for (final DVDocsBlock block in page.blocks)
            if (block.anchor != null) block.anchor!,
        for (final DVDocsPage page in site.document.pages)
          for (final DVDocsBlock block in page.blocks)
            if (block is DVDocsTable)
              for (final DVDocsRow row in block.rows)
                if (row.id != null) row.id!,
      };
      final List<String> ids = <String>[
        for (final Map<String, Object?> m
            in (graph['models']! as List<Object?>)
                .cast<Map<String, Object?>>()) ...<String>[
          'model-${m['name']}',
          for (final Object? f in m['fields']! as List<Object?>)
            'field-${m['name']}-${(f! as Map<String, Object?>)['name']}',
        ],
        for (final Object? r in graph['routes']! as List<Object?>)
          'route-${(r! as Map<String, Object?>)['path']}',
        for (final Object? f in graph['functions']! as List<Object?>)
          'function-${(f! as Map<String, Object?>)['name']}',
        for (final Object? j in graph['jobs']! as List<Object?>)
          'job-${(j! as Map<String, Object?>)['name']}',
      ];
      expect(ids, isNotEmpty);
      for (final String id in ids) {
        expect(anchors, contains(id), reason: id);
      }
    });
  });

  group('determinism', () {
    test('one input, two locations, identical bytes', () async {
      final Directory a = _write(_project, prefix: 'dv_docs_a_');
      final Directory b = _write(_project, prefix: 'dv_docs_bb_');
      final DVDocsSite first = await DVDocsSite.build(root: a.path);
      final DVDocsSite again = await DVDocsSite.build(root: a.path);
      final DVDocsSite elsewhere = await DVDocsSite.build(root: b.path);
      expect(first.files.keys, isNotEmpty);
      expect(again.files, first.files);
      expect(elsewhere.files, first.files);
      for (final MapEntry<String, String> file in first.files.entries) {
        expect(file.value, isNot(contains(a.path)), reason: file.key);
        expect(
          file.value,
          isNot(contains(p.basename(a.path))),
          reason: file.key,
        );
      }
    });

    test(
      'decisions are listed by file name, not by when they were written',
      () async {
        final Map<String, String> files = Map<String, String>.of(_project)
          ..['docs/decisions/0003-queues.md'] = '# 3. Queues\n\nNothing.\n'
          ..['docs/decisions/0002-auth.md'] = '# 2. Auth\n\nNothing.\n';
        final DVDocsSite site = await _siteFor(files);

        expect(
          site.document.pages
              .where((DVDocsPage p) => p.id.startsWith('decision:'))
              .map((DVDocsPage p) => p.id),
          <String>[
            'decision:0001-checkout',
            'decision:0002-auth',
            'decision:0003-queues',
          ],
        );
      },
    );

    test(
      'writing the site removes pages the build no longer produces',
      () async {
        final Directory root = _write(
          Map<String, String>.of(_project)
            ..['docs/decisions/0009-removed.md'] = '# 9. Removed\n',
        );
        final String out = p.join(root.path, 'build', 'docs');
        (await DVDocsSite.build(root: root.path)).writeTo(out);
        // An earlier build wrote nine pages of HTML here, and they are still
        // in the directory. The next build clears them: a documentation site
        // that answers at /models.html as well as /models is two sites, and
        // the one nobody maintains is the one that gets found.
        final File stalePage = File(p.join(out, 'models.html'));
        stalePage.writeAsStringSync('<!doctype html><html></html>');
        final File stale = File(p.join(out, 'decisions', '0009-removed.html'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('<!doctype html><html></html>');

        File(
          p.join(root.path, 'docs', 'decisions', '0009-removed.md'),
        ).deleteSync();
        final DVDocsSite site = await DVDocsSite.build(root: root.path);
        site.writeTo(out);

        expect(stale.existsSync(), isFalse, reason: 'a deleted decision');
        expect(stalePage.existsSync(), isFalse, reason: 'a page of markup');
        expect(
          File(p.join(out, dvDocsPayloadFile)).readAsStringSync(),
          site.file(dvDocsPayloadFile),
        );
        expect(
          File(p.join(out, dvDocsGraphFile)).existsSync(),
          isTrue,
          reason: 'the graph is published beside the document',
        );
      },
    );

    test(
      'refuses to clear a directory the documentation build did not write',
      () async {
        final Directory root = _write(_project);
        final DVDocsSite site = await DVDocsSite.build(root: root.path);
        // --output lib by mistake: removing what the site does not produce
        // would delete the application.
        expect(() => site.writeTo(p.join(root.path, 'lib')), throwsStateError);
        expect(
          File(p.join(root.path, 'lib', 'models', 'user.dart')).existsSync(),
          isTrue,
        );
      },
    );
  });
}
