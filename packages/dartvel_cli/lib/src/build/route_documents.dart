/// Each route's crawler-visible document, from its semantics capture, laid
/// out from its SSR-first layout capture when the build has one.
///
/// The layout is a pure function of a route's two capture files and the
/// fonts, and it is the slow part: a site of 225 routes spent 23 seconds
/// laying its documents out one after another on one core. They are worked
/// out in isolates, a share of the routes each, and handed back in the order
/// asked for, so what the build writes is what the loop wrote.
library;

import 'dart:io';
import 'dart:isolate';

import 'semantic_html.dart';
import 'semantics_capture.dart' show dvSemanticsPathFor;
import 'package:dartvel_core/dartvel.dart' show DVLayoutFont;

import 'ssr_first_capture.dart' show dvApplySsrFirstLayout;

/// [route]'s document, or null when it has no capture or its tree is empty
/// (the caller falls back to the page text).
String? dvRouteSemanticHtml(
  String root,
  String route, {
  required bool ssrFirst,
  required Map<String, List<DVLayoutFont>> fonts,
}) {
  final File file = File(dvSemanticsPathFor(root, route));
  if (!file.existsSync()) return null;
  final String html = dvSemanticHtml(DVSemanticNode.listFromJson(file.readAsStringSync()));
  if (html.trim().isEmpty) return null;
  if (!ssrFirst) return html;
  return dvApplySsrFirstLayout(root, route, html, fonts);
}

/// [dvRouteSemanticHtml] for every one of [routes], on up to [workers]
/// isolates (by default the cores, less one for the build itself).
Future<Map<String, String?>> dvRouteSemanticHtmlInParallel(
  String root,
  List<String> routes, {
  required bool ssrFirst,
  required Map<String, List<DVLayoutFont>> fonts,
  int? workers,
}) async {
  final int count = (workers ?? Platform.numberOfProcessors - 1).clamp(1, routes.isEmpty ? 1 : routes.length);
  // Every count-th route, so a run of long pages is shared out.
  final List<List<String>> shares = <List<String>>[
    for (int share = 0; share < count; share++)
      <String>[for (int index = share; index < routes.length; index += count) routes[index]],
  ];
  final List<Map<String, String?>> done = await Future.wait(<Future<Map<String, String?>>>[
    for (final List<String> share in shares)
      Isolate.run(() => <String, String?>{
        for (final String route in share) route: dvRouteSemanticHtml(root, route, ssrFirst: ssrFirst, fonts: fonts),
      }),
  ]);
  final Map<String, String?> all = <String, String?>{for (final Map<String, String?> part in done) ...part};
  return <String, String?>{for (final String route in routes) route: all[route]};
}
