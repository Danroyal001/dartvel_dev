// The crawler-visible document of every route, worked out on several cores.
//
// Laying each route's document out from its SSR-first capture is the same
// pure function per route, and on a site of 225 routes it took 23 seconds
// on one core, after the theme had taken 26 more. Spread over isolates the
// documents must be exactly the ones the one-at-a-time loop made.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/route_documents.dart';
import 'package:dartvel_cli/src/build/semantics_capture.dart' show dvSemanticsPathFor;
import 'package:test/test.dart';

void main() {
  late Directory root;
  final List<String> routes = <String>['/', '/about', '/blog/first-post', '/missing', '/empty'];

  setUp(() {
    root = Directory.systemTemp.createTempSync('route_documents');
    for (final String route in routes.where((String r) => r != '/missing')) {
      final File tree = File(dvSemanticsPathFor(root.path, route))..parent.createSync(recursive: true);
      tree.writeAsStringSync(route == '/empty'
          ? '[]'
          : jsonEncode(<Object?>[
              <String, Object?>{'role': 'heading', 'level': 1, 'label': 'Page $route', 'children': <Object?>[]},
              <String, Object?>{'role': 'link', 'label': 'Next after $route', 'href': '/next$route', 'children': <Object?>[]},
            ]));
    }
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('in parallel, every route gets exactly the document the one-at-a-time loop gives it', () async {
    for (final bool ssrFirst in <bool>[false, true]) {
      final Map<String, String?> sequential = <String, String?>{
        for (final String route in routes) route: dvRouteSemanticHtml(root.path, route, ssrFirst: ssrFirst, fonts: const {}),
      };
      final Map<String, String?> parallel =
          await dvRouteSemanticHtmlInParallel(root.path, routes, ssrFirst: ssrFirst, fonts: const {}, workers: 3);
      expect(parallel, sequential);
      expect(parallel.keys.toList(), routes, reason: 'in the order asked for');
      expect(parallel['/about'], contains('Page /about'));
      expect(parallel['/missing'], isNull, reason: 'no capture: the caller falls back');
      expect(parallel['/empty'], isNull, reason: 'an empty tree is no document');
    }
  });
}
