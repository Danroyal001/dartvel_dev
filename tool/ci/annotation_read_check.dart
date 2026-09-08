/// Fails when an annotation argument is declared and read by nothing.
///
/// This is the shape of nearly every gap found in this repository, and each
/// one was found by hand, late:
///
///   * `@DVPage(policy:)` was the specification's own usage example and the
///     generator never read it, so a page that declared a guard was open.
///   * `@DVModel(billable:)` and `nativePrice:` were declared, unit tested
///     for holding the value they were given, and looked at by nothing --
///     a model marked billable generated what an unbillable one did.
///   * `@DVModel(favicon:)` did not exist while `DVPageData.favicon` was
///     emitted by the head writer and set by nothing.
///   * `@DVPage(sitemap:)` was in the specification and in no Dart file.
///
/// The failure is always the same and always quiet: the argument is
/// accepted, the build succeeds, and the thing it asked for does not happen.
/// A developer who wrote it has decided something, and silence reads as
/// agreement.
///
/// The test is deliberately weak in the direction of allowing. It asks
/// whether the parameter's name appears anywhere a parser would look --
/// quoted, or as a key in a pattern -- outside the annotations library and
/// outside tests. That misses an argument read by a name it does not have,
/// and it will not catch one read into a variable and then dropped. What it
/// does catch is the case every one of the above was: a name that appears
/// in exactly one file and nowhere else.
///
/// A waiver needs a reason, and the reason is the point: an argument that is
/// deliberately unread is a decision somebody made, and writing it down here
/// is how the next person finds out it was deliberate.
library;

import 'dart:io';

/// Arguments that are declared and knowingly read by nothing.
const Map<String, String> waived = <String, String>{
  'DVSensitiveModelField.showInAdmin':
      'Gates nothing, deliberately. Model.Admin renders the same generated '
          'form, so a sensitive field is already excluded from the admin by '
          'the form that builds it. Meaning it would need a second set of '
          'controls, admin only, and a flag that silently did what '
          'showInForms does would look like a narrower permission was being '
          'honoured. Recorded under Sensitive Model Fields.',
};

void main() {
  final File annotations = File(
    'packages/dartvel_core/lib/src/annotations/annotations.dart',
  );
  if (!annotations.existsSync()) {
    stderr.writeln('annotation-read: ${annotations.path} is not there');
    exit(1);
  }
  final String source = annotations.readAsStringSync();

  final List<(String, String)> parameters = _parametersIn(source);
  if (parameters.isEmpty) {
    // The parser found nothing, which means it stopped matching rather than
    // that the annotations lost their arguments. A check that silently
    // passes because it read nothing is the thing this file exists to stop.
    stderr.writeln('annotation-read: no annotation parameters were found at '
        'all, so this check is reading nothing. Fix the parser here rather '
        'than assuming the annotations are empty.');
    exit(1);
  }

  final String haystack = _searchable();
  final List<String> unread = <String>[];
  for (final (String owner, String parameter) in parameters) {
    final String key = '$owner.$parameter';
    if (waived.containsKey(key)) continue;
    if (_mentioned(haystack, parameter)) continue;
    unread.add(key);
  }

  if (unread.isNotEmpty) {
    stderr.writeln('annotation-read: declared and read by nothing:');
    for (final String name in unread) {
      stderr.writeln('  $name');
    }
    stderr.writeln('');
    stderr.writeln('Each of these is an argument somebody can write that '
        'changes nothing, on a build that succeeds. Read it where the '
        'annotation is parsed, or waive it in tool/ci/annotation_read_check '
        'with the reason it is deliberately inert.');
    exit(1);
  }

  stdout.writeln('annotation-read: ${parameters.length} arguments across '
      'the annotations, ${waived.length} waived, every other one read '
      'somewhere.');
}

/// `(class, parameter)` for every `this.x` in an annotation's constructor.
List<(String, String)> _parametersIn(String source) {
  final RegExp classes = RegExp(r'class\s+(DV[A-Za-z0-9_]*)\s*\{');
  final List<RegExpMatch> found = classes.allMatches(source).toList();
  final List<(String, String)> parameters = <(String, String)>[];
  for (int i = 0; i < found.length; i++) {
    final String name = found[i].group(1)!;
    final int start = found[i].end;
    final int end = i + 1 < found.length ? found[i + 1].start : source.length;
    final RegExpMatch? constructor = RegExp(
      'const\\s+$name\\(\\{(.*?)\\}\\)',
      dotAll: true,
    ).firstMatch(source.substring(start, end));
    if (constructor == null) continue;
    for (final RegExpMatch parameter
        in RegExp(r'this\.([A-Za-z0-9_]+)').allMatches(constructor.group(1)!)) {
      parameters.add((name, parameter.group(1)!));
    }
  }
  return parameters;
}

/// Every Dart file that could read an annotation, as one string.
///
/// Tests are excluded on purpose. A parameter mentioned only by the test
/// that asserts the annotation holds it is exactly the case this check is
/// for: billable and nativePrice each had one of those and nothing else.
String _searchable() {
  final StringBuffer buffer = StringBuffer();
  for (final String root in <String>['packages', 'tool', 'examples']) {
    final Directory directory = Directory(root);
    if (!directory.existsSync()) continue;
    for (final FileSystemEntity entity in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.contains('/test/')) continue;
      if (entity.path.endsWith('annotations/annotations.dart')) continue;
      buffer.writeln(entity.readAsStringSync());
    }
  }
  return buffer.toString();
}

/// Whether [parameter] appears anywhere a parser would look for it.
///
/// Four forms, because the generators use all four and a matcher that knew
/// only some of them reported a false positive on its first real run:
/// `searchable` is read by `RegExp(r'\bsearchable\s*:\s*true\b')`, whose
/// source text contains neither a quoted name nor a real colon after it.
///
///   * `'name'` or `"name"` -- passed to a helper that pulls the argument.
///   * `name:` with a real colon -- emitted into generated source.
///   * `\bname\s` -- the name inside a raw-string regular expression, which
///     is how most of the annotation arguments are actually parsed.
bool _mentioned(String haystack, String parameter) =>
    haystack.contains("'$parameter'") ||
    haystack.contains('"$parameter"') ||
    RegExp('\\b$parameter\\s*:').hasMatch(haystack) ||
    haystack.contains('\\b$parameter\\s');
