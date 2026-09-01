/// Collecting the translatable strings out of a project.
///
/// Dartvel had typed keys and a catalogue to put them in, and nothing that
/// found them. Every key had to be written twice -- once as a constant and
/// again in each locale file -- with no check that the two agreed, which is
/// how a locale silently ends up missing half its strings.
library dartvel_cli.i18n.extract;

import 'dart:convert';

/// Every `DVTranslationKey('...')` in [source].
///
/// A scanner rather than an analyser: the key is always a literal string in a
/// const constructor, which is a shape a scanner reads exactly. What it has to
/// be careful about is not the parse but the false positives -- an example in
/// a doc comment becomes a key nobody translates, and a missing-translation
/// report that cries wolf gets ignored.
Set<String> dvExtractKeys(String source) {
  final Set<String> keys = <String>{};
  final String stripped = _stripCommentsAndStrings(source);

  final RegExp pattern = RegExp(
    r'''DVTranslationKey\s*\(\s*(['"])(.*?)\1''',
    dotAll: false,
  );

  for (final RegExpMatch match in pattern.allMatches(stripped)) {
    final String key = match.group(2)!;
    if (key.isEmpty) continue;
    // A key assembled at runtime cannot be extracted, and emitting the literal
    // fragment would put a key in the catalogue that never matches anything.
    if (key.contains(r'$')) continue;
    keys.add(key);
  }
  return keys;
}

/// Blanks out comments and string bodies, keeping the offsets that matter.
///
/// The DVTranslationKey call itself contains a string, so its own argument has
/// to survive: only strings that are *not* the argument of such a call are
/// removed. Done by blanking any string that is not immediately preceded by
/// `DVTranslationKey(`.
String _stripCommentsAndStrings(String source) {
  final StringBuffer out = StringBuffer();
  int i = 0;

  while (i < source.length) {
    final String c = source[i];

    // A line comment runs to the end of its line, including any quotes in it.
    if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      while (i < source.length && source[i] != '\n') {
        i += 1;
      }
      continue;
    }

    if (c == '/' && i + 1 < source.length && source[i + 1] == '*') {
      i += 2;
      while (i + 1 < source.length &&
          !(source[i] == '*' && source[i + 1] == '/')) {
        i += 1;
      }
      i += 2;
      continue;
    }

    if (c == "'" || c == '"') {
      final int start = i;
      int j = i + 1;
      while (j < source.length && source[j] != c) {
        if (source[j] == r'\' && j + 1 < source.length) j += 1;
        j += 1;
      }
      final int end = j < source.length ? j + 1 : source.length;

      // Kept only when this string is the argument of a DVTranslationKey call.
      // Every other string is blanked, so a sentence that happens to mention
      // the constructor does not declare a key.
      final String before = out.toString();
      final bool isKeyArgument = RegExp(r'DVTranslationKey\s*\(\s*$')
          .hasMatch(before);

      if (isKeyArgument) {
        out.write(source.substring(start, end));
      } else {
        // Replaced with an empty literal so the surrounding syntax still
        // reads, and no content inside can match.
        out.write('$c$c');
      }
      i = end;
      continue;
    }

    out.write(c);
    i += 1;
  }

  return out.toString();
}

/// What a locale is missing, and what it has that nothing declares.
class DVI18nReport {
  const DVI18nReport({
    required this.locale,
    required this.missing,
    required this.stale,
  });

  final String locale;

  /// Declared in the project, absent from this locale.
  final Set<String> missing;

  /// Present in this locale, declared nowhere. Usually a rename.
  final Set<String> stale;

  bool get isComplete => missing.isEmpty && stale.isEmpty;
}

/// Compares the declared keys against one locale's catalogue.
DVI18nReport dvCompareCatalogue({
  required Set<String> keys,
  required Set<String> translated,
  required String locale,
}) =>
    DVI18nReport(
      locale: locale,
      missing: keys.difference(translated),
      // The direction nobody notices: a key is renamed and every locale keeps
      // the old string forever.
      stale: translated.difference(keys),
    );

/// One locale's catalogue, as ARB.
///
/// ARB because it is what the Dart and Flutter localisation tooling already
/// reads, so a translator's existing workflow applies unchanged.
String dvCatalogueJson({
  required String locale,
  required Set<String> keys,
  required Map<String, String> existing,
}) {
  // Sorted, so a regenerated file has a readable diff. An unordered map means
  // every extraction reshuffles the file and the diff is the whole thing,
  // which is how translation review stops happening.
  final List<String> all = <String>{...keys, ...existing.keys}.toList()..sort();

  final Map<String, Object?> out = <String, Object?>{'@@locale': locale};
  for (final String key in all) {
    // Existing translations are never overwritten. This is the one behaviour
    // that, if wrong, destroys something a person spent hours on -- including
    // for a key that has gone: dropping it discards a translation over what
    // may be a temporary rename, so it stays and the report names it.
    out[key] = existing[key] ?? '';
  }

  return '${const JsonEncoder.withIndent('  ').convert(out)}\n';
}

/// The translations in an ARB document.
Map<String, String> dvParseCatalogue(String source) {
  final Object? decoded = jsonDecode(source);
  if (decoded is! Map) return <String, String>{};

  final Map<String, String> out = <String, String>{};
  for (final MapEntry<Object?, Object?> entry in decoded.entries) {
    final String key = '${entry.key}';
    // ARB metadata is not a translation, and counting it as one makes every
    // catalogue look like it has a key nobody declared.
    if (key.startsWith('@')) continue;
    final Object? value = entry.value;
    if (value is String) out[key] = value;
  }
  return out;
}
