// What a web-server build tells the server about guarded routes and about
// shell-first streaming.
//
// `dartvel.web.server.streaming: shell` sends a route's head before its data
// resolves, and a status code cannot follow a 200 already on the wire. A
// guarded route answers a signed-out request exactly as a route that does not
// exist, and that answer depends on the request -- so the server must know,
// before it sends anything, that a route is guarded. The build knows; the
// manifest is how the server does.
import 'dart:convert';

import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:test/test.dart';

Map<String, Object?> manifest({
  Set<String> guarded = const <String>{},
  DVWebServerSettings server = const DVWebServerSettings(),
}) =>
    jsonDecode(dvWebServerManifest(
      routes: const <String>['/', '/account/:id'],
      titles: const <String, String>{'/': 'Home', '/account/:id': 'Account'},
      text: const <String, List<String>>{},
      siteUrl: null,
      server: server,
      guarded: guarded,
    )) as Map<String, Object?>;

void main() {
  test('a guarded route is marked as one', () {
    final Map<String, Object?> routes =
        manifest(guarded: <String>{'/account/:id'})['routes']!
            as Map<String, Object?>;
    expect((routes['/account/:id']! as Map<String, Object?>)['guarded'], true);
  });

  test('a route that is not guarded carries no marker at all', () {
    // Absent rather than false, so a manifest from before the marker existed
    // and one from after it read the same for every unguarded route.
    final Map<String, Object?> routes =
        manifest(guarded: <String>{'/account/:id'})['routes']!
            as Map<String, Object?>;
    expect((routes['/']! as Map<String, Object?>).containsKey('guarded'),
        isFalse);
  });

  test('shell reaches the manifest from the declaration', () {
    final DVWebServerSettings declared =
        DVWebServerSettings.parse(<String, Object?>{'streaming': 'shell'});
    expect(
      (manifest(server: declared)['server']! as Map<String, Object?>)[
          'streaming'],
      'shell',
    );
  });
}
