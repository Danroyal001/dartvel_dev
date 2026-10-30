/// DV-STATE-003: a framework string is a literal rather than an i18n key.
///
/// The words a widget says to an application's readers are i18n keys with
/// catalogue defaults (`DVFrameworkStrings`), so they localise and rebrand
/// like everything else the application says. A literal is the silent way that
/// breaks: the English reads as a plausible rendering in every locale, so a
/// French application keeps saying "Page not found" and nothing looks wrong.
///
/// Read lexically, as the tooltip rule is, and conservatively: a literal is
/// reported only where it is unmistakably shown to a reader --
///
/// * the text of a `Text(`, `DVText(` or `SelectableText(`;
/// * a `label:`, `labelText:`, `hintText:`, `helperText:`, `errorText:`,
///   `tooltip:`, `semanticLabel:` or `semanticsLabel:` argument;
/// * a `.tooltip(` or `.semanticLabel(` modifier.
///
/// and only when the literal has words of its own once its interpolations are
/// removed: `'${map['title'] ?? ''}'` passes a value through and says nothing,
/// while `'row ${r + 1} of $total'` says "row ... of" in English. Adjacent
/// literals are one string to the compiler and one finding here.
library dartvel_cli.analysis.framework_strings_lint;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'dart_source_lexer.dart';

/// One literal a widget shows where a framework string belongs.
class DVFrameworkStringFinding {
  const DVFrameworkStringFinding({
    required this.path,
    required this.line,
    required this.text,
  });

  final String path;
  final int line;

  /// The literal as written, adjacent parts joined.
  final String text;

  /// The diagnostic this finding is.
  String get code => 'DV-STATE-003';

  @override
  String toString() => '$path:$line  $code warning: "$text" is a literal. '
      'Say it through DV.I18n.t with a DVFrameworkStrings key, whose catalogue '
      'default is the English.';
}

/// The directories of `dartvel_flutter` its developer tools live in.
///
/// Studio, the admin screens, the dev client and the docs viewer are read by
/// the person building an application rather than by its readers, and are
/// English by design; everything else a Dartvel widget shows reaches an
/// application's readers.
const List<String> dvDeveloperToolDirectories = <String>[
  'lib/src/studio/',
  'lib/src/admin/',
  'lib/src/devclient/',
  'lib/src/docs/',
  'lib/src/testing/',
];

final RegExp _textCall =
    RegExp(r'(?<![\w$.])(?:Text|DVText|SelectableText)\s*\(');
final RegExp _namedArgument = RegExp(
  r'(?<![\w$.])(?:label|labelText|hintText|helperText|errorText|tooltip|semanticLabel|semanticsLabel)\s*:',
);
final RegExp _modifierCall = RegExp(r'\.(?:tooltip|semanticLabel)\s*\(');
final RegExp _aLetter = RegExp(r'\p{L}', unicode: true);

/// Findings in one source file.
List<DVFrameworkStringFinding> dvFindLiteralFrameworkStrings({
  required String path,
  required String source,
}) {
  final DVDartSourceView view = dvDartSourceView(source);
  // Patterns are matched where strings and comments are blanked, so a word
  // in a doc comment is never read as a call; the literal itself is read from
  // the source with only comments blanked.
  final String masked = view.masked;
  final String code = view.code;
  final Map<int, DVFrameworkStringFinding> byOffset =
      <int, DVFrameworkStringFinding>{};

  for (final RegExp pattern in <RegExp>[_textCall, _namedArgument, _modifierCall]) {
    for (final RegExpMatch match in pattern.allMatches(masked)) {
      var at = match.end;
      while (at < code.length && code[at].trim().isEmpty) {
        at++;
      }
      final StringBuffer text = StringBuffer();
      final StringBuffer words = StringBuffer();
      var any = false;
      while (true) {
        final ({String words, String content, int end})? span =
            dvDartStringLiteralSpan(code, at);
        if (span == null) break;
        any = true;
        text.write(span.content);
        words.write(span.words);
        at = span.end;
        while (at < code.length && code[at].trim().isEmpty) {
          at++;
        }
      }
      if (!any || !_aLetter.hasMatch(words.toString())) continue;
      byOffset[match.end] = DVFrameworkStringFinding(
        path: path,
        line: dvDartLineOf(source, match.end),
        text: text.toString(),
      );
    }
  }
  final List<int> offsets = byOffset.keys.toList()..sort();
  return <DVFrameworkStringFinding>[for (final int o in offsets) byOffset[o]!];
}

/// Every Dart file under the package at [root]'s `lib/`, except generated
/// code and the directories [exclude] names (relative to [root], with `/`).
List<DVFrameworkStringFinding> dvScanForLiteralFrameworkStrings(
  String root, {
  List<String> exclude = const <String>[],
}) {
  final Directory lib = Directory(p.join(root, 'lib'));
  if (!lib.existsSync()) return const <DVFrameworkStringFinding>[];
  final List<File> files = lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .where((File f) =>
          !RegExp(r'\.(g|freezed|dv|generated)\.dart$').hasMatch(f.path))
      .where((File f) =>
          !f.path.contains('${p.separator}generated${p.separator}'))
      .where((File f) {
        final String relative =
            p.relative(f.path, from: root).replaceAll(r'\', '/');
        return !exclude.any(relative.startsWith);
      })
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
  return <DVFrameworkStringFinding>[
    for (final File file in files)
      ...dvFindLiteralFrameworkStrings(
        path: p.relative(file.path, from: root),
        source: file.readAsStringSync(),
      ),
  ];
}
