/// A page's Content-Security-Policy built from the inline scripts it sends.
///
/// A Dartvel page carries inline scripts of its own: the splash, the renderer
/// hints, the first-frame hand-over. Their text changes between builds, so a
/// policy that lists their hashes by hand (in a proxy, or in pubspec.yaml) is
/// right for exactly one build. On 9 Nov 2026 a proxy kept the hashes of the
/// previous build, the browser refused the new scripts, and the app never
/// started; the page stayed server-rendered for a day.
///
/// So the server lists them itself. A policy written with the source
/// `'inline-scripts'` has it replaced, on each page, with the `sha256-` hash
/// of every inline script in that page's HTML. A page with none drops the
/// token: it is never widened into `'unsafe-inline'`.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The source in a policy that stands for the page's own inline scripts.
const String dvInlineScriptsSource = "'inline-scripts'";

final RegExp _script = RegExp(r'<script\b([^>]*)>([\s\S]*?)</script\s*>', caseSensitive: false);
final RegExp _src = RegExp(r'''\ssrc\s*=''', caseSensitive: false);
final RegExp _type = RegExp(r'''\stype\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''', caseSensitive: false);

/// The types a browser runs as script; anything else (JSON-LD, page data) is
/// a data block that script-src does not govern.
bool _runs(String? type) {
  if (type == null) return true;
  final String value = type.trim().toLowerCase();
  return value.isEmpty ||
      value == 'module' ||
      value == 'text/javascript' ||
      value == 'application/javascript' ||
      value == 'text/ecmascript' ||
      value == 'application/ecmascript';
}

/// `'sha256-…'` for each distinct inline script in [html] that a browser
/// would run, in page order. External scripts (`src=`) are left to the
/// policy's own sources.
List<String> dvInlineScriptHashes(String html) {
  final List<String> hashes = <String>[];
  for (final RegExpMatch match in _script.allMatches(html)) {
    final String attributes = match.group(1) ?? '';
    if (_src.hasMatch(' $attributes')) continue;
    final RegExpMatch? type = _type.firstMatch(' $attributes');
    if (!_runs(type == null ? null : (type.group(1) ?? type.group(2) ?? type.group(3)))) continue;
    final String digest = base64.encode(sha256.convert(utf8.encode(match.group(2) ?? '')).bytes);
    final String source = "'sha256-$digest'";
    if (!hashes.contains(source)) hashes.add(source);
  }
  return hashes;
}

/// [policy] with [dvInlineScriptsSource] replaced by the hashes of [html]'s
/// inline scripts. [extraHtml] adds the scripts of other HTML that may reach
/// the same response (a streamed page's shell, before and after minifying).
String dvPageContentSecurityPolicy(String policy, String html, {Iterable<String> extraHtml = const <String>[]}) {
  if (!policy.contains(dvInlineScriptsSource)) return policy;
  final List<String> hashes = <String>[...dvInlineScriptHashes(html)];
  for (final String more in extraHtml) {
    for (final String hash in dvInlineScriptHashes(more)) {
      if (!hashes.contains(hash)) hashes.add(hash);
    }
  }
  final String replacement = hashes.join(' ');
  return policy
      .replaceAll(dvInlineScriptsSource, replacement)
      .replaceAll(RegExp(r' {2,}'), ' ')
      .replaceAll(RegExp(r' +;'), ';')
      .trim();
}
