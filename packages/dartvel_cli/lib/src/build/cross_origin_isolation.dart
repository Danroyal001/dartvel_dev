/// Whether a web-server build can make its pages cross-origin isolated.
///
/// skwasm (the default WebAssembly renderer) draws on a worker thread only on
/// a cross-origin isolated page, which takes two response headers:
/// `Cross-Origin-Opener-Policy: same-origin` and
/// `Cross-Origin-Embedder-Policy: credentialless`. What they break:
///
/// * COOP `same-origin` puts the page in a browsing-context group of its own.
///   A popup it opens on another site (a sign-in or payment window, Google
///   Identity Services' popup mode) loses `window.opener`, so the popup
///   cannot report back, and a page that opened this one loses its handle.
/// * COEP `credentialless` loads another site's images, scripts and fonts
///   without cookies (one that needs them fails), and refuses an iframe from
///   another site unless that site opts in -- a map, a video player, a
///   payment form or a webview drawn into a platform view.
///
/// Nothing on the application's own origin is affected. So the build turns
/// isolation on by default for a wasm build and off when it finds any sign
/// of the cases above; `dartvel.web.crossOriginIsolated` decides outright.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Packages known to open a popup on another site or draw another site's
/// page into a platform view.
const Set<String> dvCrossOriginEmbeddingPackages = <String>{
  'google_sign_in',
  'google_sign_in_web',
  'firebase_auth',
  'firebase_ui_auth',
  'webview_flutter',
  'webview_flutter_web',
  'flutter_inappwebview',
  'google_maps_flutter',
  'google_maps_flutter_web',
  'youtube_player_iframe',
  'pay',
  'flutter_stripe',
  'flutter_stripe_web',
  'flutter_paystack',
};

/// What in the project at [root] cross-origin isolation would break, one
/// sentence each; empty when the build found nothing.
List<String> dvCrossOriginIsolationBlockers(String root) {
  final List<String> reasons = <String>[];

  final File index = File(p.join(root, 'web', 'index.html'));
  if (index.existsSync()) {
    final String html = index.readAsStringSync();
    for (final RegExpMatch script in RegExp(
            r'''<script\b[^>]*\bsrc\s*=\s*["']((?:https?:)?//[^/"']+)''',
            caseSensitive: false)
        .allMatches(html)) {
      reasons.add('web/index.html loads a script from ${script.group(1)}, '
          'which may open a popup or an iframe of its own.');
    }
    if (RegExp(r'<iframe\b', caseSensitive: false).hasMatch(html)) {
      reasons.add('web/index.html has an iframe, which COEP refuses unless '
          'its site opts in.');
    }
  }

  final Directory lib = Directory(p.join(root, 'lib'));
  if (lib.existsSync()) {
    for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String relative =
          p.relative(entity.path, from: root).replaceAll(r'\', '/');
      // The generated client is the framework's, not the application's.
      if (relative.startsWith('lib/dartvel_client/')) continue;
      final String source = entity.readAsStringSync();
      if (RegExp(r'\bHtmlElementView\b|\bHTMLIFrameElement\b|'
              r'''createElement\(\s*['"]iframe['"]''')
          .hasMatch(source)) {
        reasons.add('$relative puts web content in a platform view, which '
            'COEP refuses when it comes from another site.');
      }
    }
  }

  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (pubspec.existsSync()) {
    final Object? parsed = loadYaml(pubspec.readAsStringSync());
    final Object? dependencies = parsed is Map ? parsed['dependencies'] : null;
    if (dependencies is Map) {
      for (final Object? name in dependencies.keys) {
        if (dvCrossOriginEmbeddingPackages.contains(name)) {
          reasons.add('pubspec.yaml depends on $name, which opens a popup '
              'or draws a page from another site.');
        }
      }
    }
  }
  return reasons;
}
