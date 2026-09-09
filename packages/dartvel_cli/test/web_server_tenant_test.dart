// The preview and web-server handler renders as the tenant that asked.
//
// The page a developer previews is meant to be the page the server sends.
// This handler resolved no tenant, so a page whose data comes from a
// tenant-scoped model rendered the default tenant's rows here while the
// deployed server rendered the caller's -- and the divergence shows up as a
// page that looks right locally and wrong once it is live.
import 'dart:io';

import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:dartvel_core/dartvel.dart' show DVTenantSource, DVTenants;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

const String _shell =
    '<!DOCTYPE html>\n<html><head><title>App</title></head><body></body></html>';

const String _manifest = '''
{
  "siteUrl": "https://example.com",
  "server": {"pageDataMode": "cache"},
  "routes": {"/orders": {"title": "Orders"}}
}
''';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_ws_tenant_');
    File(p.join(root.path, 'index.html')).writeAsStringSync(_shell);
    File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(_manifest);
    // The header source, because a test server answers on localhost and a
    // host with no domain under it names no tenant by design.
    const DVTenants().configure(source: DVTenantSource.header);
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    DVTenants.reset();
  });

  Future<String> get(String tenant, Handler handler) async {
    final Response response = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost:8080/orders'),
        headers: <String, String>{'X-Tenant': tenant},
      ),
    );
    return response.readAsString();
  }

  test('the page data resolver runs as the tenant the request named',
      () async {
    final List<String> asked = <String>[];
    final Handler handler = dvWebServerHandler(
      webRoot: root.path,
      pageData: (DVPageRequest request) async {
        asked.add(const DVTenants().currentTenant);
        return const DVPageData(title: 'Orders');
      },
    );

    await get('acme', handler);

    expect(asked, <String>['acme']);
  });

  test('a page kept for one tenant is not served to another', () async {
    final Handler handler = dvWebServerHandler(
      webRoot: root.path,
      pageData: (DVPageRequest request) async =>
          DVPageData(title: 'Orders for ${const DVTenants().currentTenant}'),
    );

    expect(await get('acme', handler), contains('Orders for acme'));
    expect(await get('globex', handler), contains('Orders for globex'));
  });

  test('a static file is served without a page resolver being asked at all',
      () async {
    // The tenant wrapper goes around the whole handler, so this is the check
    // that it did not change what a request for a file does.
    File(p.join(root.path, 'app.js')).writeAsStringSync('console.log(1);');
    final Handler handler = dvWebServerHandler(webRoot: root.path);

    final Response response = await handler(
      Request('GET', Uri.parse('http://localhost:8080/app.js')),
    );

    expect(await response.readAsString(), 'console.log(1);');
  });
}

