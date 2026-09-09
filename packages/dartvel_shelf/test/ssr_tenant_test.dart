// The server-rendered page belongs to the tenant that asked for it.
//
// Nothing on this path had ever resolved a tenant. The page data resolver
// queries models, tenant-scoped models included, and it ran under whatever
// the process-wide tenant happened to be -- the default one on a fresh
// server, or the last tenant some other code had set. So a customer on their
// own subdomain got the default tenant's rows rendered into the title, the
// description, the structured data and the crawler-visible text, on the one
// path that a search engine then indexes.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show DVPageData, DVPageDataResolver, DVPageRequest, DVTenants;
import 'package:dartvel_core/http.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _shell =
    '<!DOCTYPE html>\n<html><head><title>Shell</title></head><body></body></html>';

Directory _site({String pageDataMode = 'await'}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_tenant_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'index.html')).writeAsStringSync(_shell);
  File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(
    jsonEncode(<String, Object?>{
      'siteUrl': 'https://example.com',
      'site': <String, Object?>{'name': 'Example'},
      'server': <String, Object?>{'pageDataMode': pageDataMode},
      'routes': <String, Object?>{
        '/orders': <String, Object?>{'title': 'Orders'},
      },
    }),
  );
  return root;
}

Future<String> _get(
  String host,
  String site, {
  required DVPageDataResolver pageData,
}) async {
  final Response response = await handleSsrFallback(
    Request(
      method: 'GET',
      url: Uri.parse('http://$host/orders'),
      headers: Headers(),
      bodyStream: const Stream<List<int>>.empty(),
    ),
    site,
    pageData: pageData,
  );
  return utf8.decode(<int>[
    for (final List<int> chunk in await response.body!.stream.toList()) ...chunk,
  ]);
}

void main() {
  tearDown(DVTenants.reset);

  test('the page data resolver runs as the tenant the host names', () async {
    final Directory site = _site();
    String? asked;

    await _get(
      'acme.example.com',
      site.path,
      pageData: (DVPageRequest request) async {
        asked = const DVTenants().currentTenant;
        return const DVPageData(title: 'Orders');
      },
    );

    expect(asked, 'acme');
  });

  test('a page kept for one tenant is not served to another', () async {
    // End to end, with the mode that keeps pages: the first tenant to ask
    // used to fill the entry for the path, and the next tenant was handed
    // that page.
    final Directory site = _site(pageDataMode: 'cache');

    Future<String> serve(String host) => _get(
          host,
          site.path,
          pageData: (DVPageRequest request) async =>
              DVPageData(title: 'Orders for ${const DVTenants().currentTenant}'),
        );

    expect(await serve('acme.example.com'), contains('Orders for acme'));
    expect(await serve('globex.example.com'), contains('Orders for globex'));
  });

  test('the tenant does not outlive the request', () async {
    await _get(
      'acme.example.com',
      _site().path,
      pageData: (DVPageRequest request) async => const DVPageData(title: 'Orders'),
    );

    expect(const DVTenants().currentTenant, DVTenants.defaultTenant);
  });
}
