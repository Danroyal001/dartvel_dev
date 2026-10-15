import 'dart:convert';

import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:test/test.dart';

void main() {
  test('the manifest carries what dartvel.hosts declared', () {
    const hostConfig = DVHostRoutingConfig(
      trustedProxies: {'127.0.0.1'},
      trustLoopback: true,
      entries: [
        DVHostEntry(
          pattern: 'sigmadev.digital',
          siteUrl: 'https://sigmadev.digital',
        ),
        DVHostEntry(
          pattern: 'tools.sigmadev.digital',
          siteUrl: 'https://tools.sigmadev.digital',
          mount: '/tools',
        ),
        DVHostEntry(
          pattern: '*.tools.sigmadev.digital',
          siteUrl: 'https://{slug}.tools.sigmadev.digital',
          mount: '/tools/{slug}',
        ),
      ],
    );

    final Map<String, Object?> manifest = jsonDecode(dvWebServerManifest(
      routes: const <String>['/', '/tools'],
      titles: const <String, String>{'/': 'Home', '/tools': 'Tools'},
      text: const <String, List<String>>{},
      siteUrl: 'https://sigmadev.digital',
      hosts: hostConfig,
    )) as Map<String, Object?>;

    expect(manifest.containsKey('hosts'), isTrue);
    final hosts = manifest['hosts'] as Map<String, Object?>;
    expect(hosts['trustLoopback'], isTrue);
    expect(hosts['trustedProxies'], contains('127.0.0.1'));
    final entries = hosts['entries'] as List<Object?>;
    expect(entries, hasLength(3));
  });

  test('a project with no hosts declared omits the hosts block', () {
    final Map<String, Object?> manifest = jsonDecode(dvWebServerManifest(
      routes: const <String>['/'],
      titles: const <String, String>{'/': 'Home'},
      text: const <String, List<String>>{},
      siteUrl: 'https://example.com',
    )) as Map<String, Object?>;

    expect(manifest.containsKey('hosts'), isFalse);
  });
}
