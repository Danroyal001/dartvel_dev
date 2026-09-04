/// Prints the semantics labels of an HTML page read on stdin.
///
///     google-chrome --dump-dom "$PAGE" | dart tool/ci/aria_labels.dart
///
/// A CanvasKit page has no text in its DOM; what it has is the semantics tree
/// Dartvel enables by default, and the labels in it carry the visible words.
/// A screenshot cannot tell a working page from the application's own 404 --
/// both have text, colour and layout -- so the step asks the page instead.
library;

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final int limit =
      arguments.isEmpty ? 20 : int.tryParse(arguments.first) ?? 20;
  final String html = await utf8.decoder.bind(stdin).join();
  final Iterable<RegExpMatch> found =
      RegExp(r'aria-label="([^"]+)"').allMatches(html);
  stdout.writeln(
      found.take(limit).map((RegExpMatch m) => m.group(1)!).join(' | '));
}
