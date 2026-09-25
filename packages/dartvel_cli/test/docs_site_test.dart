// Documentation Generation: the site is a second rendering of the project
// graph, not a second copy of it maintained by hand.
//
// What these guard is the failure a generated site can actually have. It
// cannot be out of date with the code, so it fails by being plausible and
// wrong: a sensitive field rendered like any other, a decision pointing at a
// function that was renamed, a node the AI context knows about that the site
// silently leaves out, or bytes that change between two builds of one input.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/docs/docs_site.dart';
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

/// The part of [page] from the element with [id] to the next section.
String _section(String page, String id) {
  final int start = page.indexOf('id="$id"');
  expect(start, isNot(-1), reason: 'no element with id="$id"');
  final int end = page.indexOf('<section', start + 1);
  return page.substring(start, end == -1 ? page.length : end);
}

void main() {
  group('models', () {
    test(
      'every model and field is rendered with its type and doc comment',
      () async {
        final DVDocsSite site = await _siteFor(_project);
        final String models = site.files['models.html']!;
        final String user = _section(models, 'model-User');
        expect(user, contains('A person who can sign in.'));
        expect(user, contains('id="field-User-email"'));
        expect(user, contains('Where receipts are sent.'));
        expect(user, contains('lib/models/user.dart:4'));
        expect(_section(models, 'model-Order'), contains('Who paid.'));
      },
    );

    test('a sensitive field is named and never valued', () async {
      final DVDocsSite site = await _siteFor(_project);
      final String models = site.files['models.html']!;

      // Both annotation orders, and the form with arguments. A field the
      // graph failed to mark would render as an ordinary field, with an
      // example value, and look entirely correct.
      for (final String id in <String>[
        'field-User-taxId',
        'field-Order-bankAccount',
      ]) {
        final int at = models.indexOf('id="$id"');
        expect(at, isNot(-1), reason: '$id is not named');
        final String row = models.substring(at, models.indexOf('</tr>', at));
        expect(row, contains('sensitive'), reason: '$id is not marked');
      }
      final String example = _section(models, 'model-User');
      expect(example, contains('"taxId": "[sensitive]"'));
      expect(example, contains('"email": "text"'));

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
            jsonDecode(site.files['graph.json']!) as Map<String, Object?>;
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
      final String order = _section(site.files['models.html']!, 'model-Order');
      // The relation itself, not any link to User: the field's type cell
      // links there too, and asserting on that would pass with no relations
      // rendered at all.
      expect(
        order,
        contains(
          '<li><code>buyer</code> → <a href="#model-User">User</a></li>',
        ),
      );
    });

    test('policies and generated surfaces are listed on the model', () async {
      final DVDocsSite site = await _siteFor(_project);
      final String models = site.files['models.html']!;
      final String user = _section(models, 'model-User');
      expect(user, contains('UserPolicy'));
      expect(user, contains('User.Form'));
      expect(user, contains('User.Page'));
      expect(user, contains('/users/:id'));
      // Every model gets the page component; one that opted out of public
      // pages has no route. Claiming one for Order would be a link to a 404.
      expect(_section(models, 'model-Order'), contains('Order.Page'));
      expect(_section(models, 'model-Order'), isNot(contains('/orders/:id')));
    });

    test('a doc comment is escaped, not injected', () async {
      final DVDocsSite site = await _siteFor(_project);
      final String routes = site.files['routes.html']!;
      expect(routes, isNot(contains('<script>alert(1)</script>')));
      expect(routes, contains('&lt;script&gt;alert(1)&lt;/script&gt;'));
    });
  });

  group('functions', () {
    test('a function carries its signature, doc comment and source', () async {
      final DVDocsSite site = await _siteFor(_project);
      final String checkout = _section(
        site.files['functions.html']!,
        'function-checkout',
      );
      expect(checkout, contains('POST'));
      expect(checkout, contains('/checkout'));
      expect(
        checkout,
        contains(
          'Future&lt;String&gt; checkout(DVContext context, String basketId)',
        ),
      );
      expect(
        checkout,
        contains('Charges the basket and returns the order id.'),
      );
      expect(checkout, contains('lib/backend/functions/checkout.post.dart:4'));
    });

    test(
      'an unannotated function is still typed, with its signature and doc',
      () async {
        // Most functions in the repository's own example carry no annotation.
        // The generator types them by signature, so the site does too.
        final DVDocsSite site = await _siteFor(_project);
        final String sum = _section(
          site.files['functions.html']!,
          'function-sum',
        );
        expect(sum, contains('int sum(int a, int b)'));
        expect(sum, contains('Adds two numbers.'));
        expect(sum, contains('data-stage="csrf"'));
      },
    );

    test(
      'the request lifecycle stages are listed in the order they run',
      () async {
        final DVDocsSite site = await _siteFor(_project);
        final String checkout = _section(
          site.files['functions.html']!,
          'function-checkout',
        );
        final List<String> stages = RegExp(
          r'<li class="stage" data-stage="([^"]+)"',
        ).allMatches(checkout).map((RegExpMatch m) => m.group(1)!).toList();
        expect(stages, <String>[
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

        final String health = _section(
          site.files['functions.html']!,
          'function-health',
        );
        final List<String> healthStages = RegExp(
          r'<li class="stage" data-stage="([^"]+)"',
        ).allMatches(health).map((RegExpMatch m) => m.group(1)!).toList();
        // A GET never has its body read, so listing that stage would describe
        // a step this request does not take.
        expect(healthStages,
            <String>['tenant', 'privacy', 'csrf', 'function']);
      },
    );
  });

  group('routes', () {
    test('pages, generated model pages and mounted module routes', () async {
      final DVDocsSite site = await _siteFor(_project);
      final String routes = site.files['routes.html']!;
      expect(_section(routes, 'route-/'), contains('The front door.'));
      expect(
        _section(routes, 'route-/admin'),
        contains('DVPolicies.viewAdmin'),
      );
      final String userPage = _section(routes, 'route-/users/:id');
      expect(userPage, contains('href="models.html#model-User"'));
      final String store = _section(routes, 'route-/store');
      expect(store, contains('store'));
      expect(store, contains('modules/store/lib/pages/index.page.dart:4'));
      expect(store, contains('The shop window.'));
    });
  });

  group('jobs and schedules', () {
    test(
      'jobs with their queue, and cron with its expression and target',
      () async {
        final DVDocsSite site = await _siteFor(_project);
        final String jobs = site.files['jobs.html']!;
        final String welcome = _section(jobs, 'job-SendWelcome');
        expect(welcome, contains('mail'));
        expect(welcome, contains('Sends the welcome email.'));

        final String nightly = _section(jobs, 'schedule-nightlyReport');
        expect(nightly, contains('0 3 * * *'));
        expect(nightly, contains('backend'));
        expect(nightly, contains('Totals the day.'));

        // A client schedule is a request, not a guarantee, and a reference
        // that printed it beside the server's as if the two were the same
        // clock would be the implied promise the specification refuses.
        final String client = _section(jobs, 'schedule-refreshDashboard');
        expect(client, contains('*/5 * * * *'));
        expect(client, contains('client'));
        expect(client, contains('not a guarantee'));
        expect(nightly, isNot(contains('not a guarantee')));
      },
    );
  });

  group('policy matrix', () {
    test('each resource against each action, and what each guards', () async {
      final DVDocsSite site = await _siteFor(_project);
      final String policies = site.files['policies.html']!;
      final String user = _section(policies, 'policy-User');
      String cell(String action) {
        final int at = user.indexOf('data-action="$action"');
        expect(at, isNot(-1), reason: 'no $action cell');
        return user.substring(at, user.indexOf('</td>', at));
      }

      expect(cell('view'), contains('UserPolicy.view'));
      expect(cell('update'), contains('UserPolicy.update'));
      // Default-deny is what the runtime does for an action nobody wrote.
      expect(cell('delete'), contains('denied'));

      final String guarded = _section(policies, 'guarded');
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
        final DVDocsSite site = await _siteFor(_project);
        final String store = _section(
          site.files['modules.html']!,
          'module-store',
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
      'pubspec.yaml':
          '''
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
      final DVDocsSite site = await _siteFor(granted(egress: "'stripe.com'"));
      final String store = _section(
        site.files['modules.html']!,
        'module-store',
      );
      expect(store, contains('Grant'));
      expect(store, contains('secrets: STORE_KEY'));
      expect(store, contains('Trust'));
      expect(store, contains('DV-MODULE-001'));
      expect(store, contains('api.example.com'));
    });

    test('says so when there is nothing to refuse', () async {
      final DVDocsSite site = await _siteFor(
        granted(egress: "'api.example.com'"),
      );
      final String store = _section(
        site.files['modules.html']!,
        'module-store',
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
      expect(site.files, contains('modules.html'));
    });
  });

  group('diagnostics glossary', () {
    test('every registered code, from the registry explain reads', () async {
      final DVDocsSite site = await _siteFor(_project);
      final String glossary = site.files['diagnostics.html']!;
      for (final DVDiagnostic d in DVDiagnostics.all) {
        expect(glossary, contains('id="${d.code}"'), reason: d.code);
      }
      expect(
        RegExp(r'<tr class="diagnostic"').allMatches(glossary).length,
        DVDiagnostics.all.length,
      );
    });
  });

  group('decision records', () {
    test(
      'a decision links to the nodes it names, and they link back',
      () async {
        final DVDocsSite site = await _siteFor(_project);
        final String decision = site.files['decisions/0001-checkout.html']!;
        expect(
          decision,
          contains('href="../functions.html#function-checkout"'),
        );
        expect(decision, contains('href="../models.html#model-Order"'));
        expect(
          decision,
          contains('Checkout charges before it writes the order'),
        );

        expect(
          _section(site.files['functions.html']!, 'function-checkout'),
          contains('href="decisions/0001-checkout.html"'),
        );
        expect(
          _section(site.files['models.html']!, 'model-Order'),
          contains('href="decisions/0001-checkout.html"'),
        );
        expect(
          site.files['index.html'],
          contains('decisions/0001-checkout.html'),
        );
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

        final String decision = site.files['decisions/0001-checkout.html']!;
        expect(decision, isNot(contains('#function-legacyCharge')));
        expect(decision, contains('class="gone"'));
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
      final String refund = _section(
        site.files['functions.html']!,
        'function-refund',
      );
      expect(refund, contains('no source to render from'));
      expect(
        _section(site.files['models.html']!, 'model-User'),
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
        expect(site.files['graph.json'], '$text\n');
      },
    );

    test('every node in that graph has a place in the site', () async {
      final DVDocsSite site = await _siteFor(_project);
      final Map<String, Object?> graph =
          jsonDecode(site.files['graph.json']!) as Map<String, Object?>;
      final String html = site.files.entries
          .where((MapEntry<String, String> e) => e.key.endsWith('.html'))
          .map((MapEntry<String, String> e) => e.value)
          .join('\n');
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
        expect(html, contains('id="$id"'), reason: id);
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
        final String index = site.files['index.html']!;
        final int one = index.indexOf('decisions/0001-checkout.html');
        final int two = index.indexOf('decisions/0002-auth.html');
        final int three = index.indexOf('decisions/0003-queues.html');
        expect(<int>[one, two, three].every((int i) => i != -1), isTrue);
        expect(one < two && two < three, isTrue);
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
        final File stale = File(p.join(out, 'decisions', '0009-removed.html'));
        expect(stale.existsSync(), isTrue);

        File(
          p.join(root.path, 'docs', 'decisions', '0009-removed.md'),
        ).deleteSync();
        final DVDocsSite site = await DVDocsSite.build(root: root.path);
        site.writeTo(out);
        // A page for a decision that was deleted is a page somebody can still
        // find and believe.
        expect(stale.existsSync(), isFalse);
        expect(
          File(p.join(out, 'index.html')).readAsStringSync(),
          site.files['index.html'],
        );
        expect(
          File(p.join(out, 'decisions', '0001-checkout.html')).existsSync(),
          isTrue,
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
