// The site search, run the way the server runs it: pages read from a route
// manifest, stored as SitePage records, searched in hybrid mode.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_site/backend/site_search.dart';
import 'package:dartvel_site/components/section_anchor.dart';
import 'package:dartvel_site/dartvel_client/dartvel_server.dart';
import 'package:flutter_test/flutter_test.dart';

const String chrome = '<a href="/">Dartvel, home</a>\n<a href="/docs">Docs</a>\n';
const String footer = '<a href="https://github.com/Danroyal001/dartvel_dev">GitHub</a>\n'
    '<p>FSL-1.1-MIT licensed. Built with Dartvel.</p>';

Map<String, Object?> route(String path, String title, List<String> body) =>
    <String, Object?>{
      'title': title,
      'text': <String>[],
      'page': <String, Object?>{
        'route': path,
        'title': title,
        'description': '',
        'html': '$chrome${body.join('\n')}\n$footer',
      },
    };

final Map<String, Map<String, Object?>> site = <String, Map<String, Object?>>{
  '/docs/deploying': route('/docs/deploying', 'Run and deploy a Dartvel backend', <String>[
    '<h1>Servers and deploying</h1>',
    '<p>The web-server build is one executable file.</p>',
    '<h2>Copy the binary to your server</h2>',
    '<p>Upload the file, point a systemd unit at it and restart. Nginx sits in front and forwards requests.</p>',
  ]),
  '/docs/cache': route('/docs/cache', 'Dartvel cache: get, set, has and delete', <String>[
    '<h1>Cache</h1>',
    '<p>Four calls: get, set, has and delete. Tags invalidate many keys at once.</p>',
  ]),
  '/docs/auth': route('/docs/auth', 'Dartvel auth: sign-in, second factor and sessions', <String>[
    '<h1>Auth and sessions</h1>',
    '<p>Sign in with a password, a passkey, Google or GitHub. Sessions are cookies.</p>',
    '<h2>Second factor</h2>',
    '<p>An authenticator app code or a passkey after the password.</p>',
  ]),
  '/docs/notifications': route('/docs/notifications', 'Dartvel notifications: email, in-app and push', <String>[
    '<h1>Notifications and mail</h1>',
    '<p>Send email through Resend, Postmark or SMTP, and push to phones.</p>',
  ]),
  '/docs/billing': route('/docs/billing', 'Dartvel billing: subscriptions, purchases, tax and usage', <String>[
    '<h1>Billing and commerce</h1>',
    '<p>Subscriptions and one-off purchases through Stripe and the app stores, with tax.</p>',
  ]),
};

Future<void> serve(Map<String, Map<String, Object?>> routes) async {
  final Directory web = Directory.systemTemp.createTempSync('site_search_web');
  addTearDown(() => web.deleteSync(recursive: true));
  File('${web.path}/dartvel_routes.json').writeAsStringSync(jsonEncode(
      <String, Object?>{'siteUrl': 'https://dartvel.dev', 'routes': routes}));
  DVSitePages.webRoot = web.path;
  resetSiteSearch();
}

void main() {
  setUpAll(() async {
    registerDartvelModels();
    const DVDatabase().configure(SqliteDVDatabaseAdapter.memory());
    // What the generated backend's migration does when the server starts.
    await const DVDatabase().execute(
        'CREATE TABLE IF NOT EXISTS sitepages (id TEXT, path TEXT, title TEXT, '
        'heading TEXT, body TEXT, _dv_version INTEGER NOT NULL DEFAULT 1, '
        '_dv_deleted_at TEXT)');
  });

  tearDown(() => DVSitePages.webRoot = null);

  Future<List<String>> paths(String q) async =>
      <String>[for (final SiteSearchResult r in await siteSearch(q)) r.path];

  test('a question finds the page that answers it', () async {
    await serve(site);

    expect((await paths('send an email')).first, '/docs/notifications');
    expect((await paths('sign in with google')).first, '/docs/auth');
    expect((await paths('stripe subscriptions')).first, '/docs/billing');
    expect((await paths('upload to my server')).first, '/docs/deploying');
  });

  test('a result names the section it matched, as a link to it', () async {
    await serve(site);

    final SiteSearchResult top = (await siteSearch('authenticator app')).first;
    expect(top.path, '/docs/auth');
    expect(top.heading, 'Second factor');
    expect(top.href, '/docs/auth#${sectionAnchor('Second factor')}');
    expect(top.href, '/docs/auth#second-factor');
  });

  test('every page is found once, however many of its sections match',
      () async {
    await serve(site);

    final List<String> found = await paths('passkey password session');
    expect(found.toSet().length, found.length);
  });

  test('the chrome every page repeats matches nothing', () async {
    await serve(site);

    // "GitHub" is in the footer of every page and in the body of one.
    expect(await paths('FSL licensed'), isEmpty);
    expect(await paths('GitHub'), <String>['/docs/auth']);
  });

  test('nothing, gibberish and a very long query are answered, not thrown',
      () async {
    await serve(site);

    expect(await paths(''), isEmpty);
    expect(await paths('   '), isEmpty);
    expect(await paths('zxqv wkjh'), isEmpty);
    expect(await siteSearch('cache ' * 10000), isNotEmpty);
  });

  test('the records follow the pages', () async {
    await serve(site);
    await siteSearch('cache');
    expect((await SitePage.all()).where((SitePage s) => s.path == '/docs/billing'),
        isNotEmpty);

    // Billing is gone from the site: its sections are gone from the model,
    // and it is not found.
    await serve(<String, Map<String, Object?>>{...site}..remove('/docs/billing'));
    expect(await paths('stripe subscriptions'), isNot(contains('/docs/billing')));
    expect((await SitePage.all()).where((SitePage s) => s.path == '/docs/billing'),
        isEmpty);
  });

  test('a snippet is cut at words, around what was asked', () {
    final String body = List<String>.generate(60, (int i) => 'word$i').join(' ');
    final String snippet = siteSearchSnippet('$body deploy here $body', 'deploy');
    expect(snippet, contains('deploy here'));
    expect(snippet, startsWith('...'));
    expect(snippet.length, lessThan(200));
  });
}
