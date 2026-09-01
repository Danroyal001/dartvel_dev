/// Public names the specification says will never exist.
///
/// The Multi-Window section closes this as a list: "No DVWindowManager, no
/// DV.Windows, no DVWindowing -- not as a public type, not as a documented
/// name, ever." A rule stated in prose comes back the first time someone needs
/// a place to put something; a rule with a check does not.
library dartvel_cli.analysis.banned_names;

/// The names, exactly as the contract states them.
const Set<String> dvBannedPublicNames = <String>{
  'DVWindowManager',
  'DVWindowing',
  'DV.Windows',
};

/// One occurrence.
class DVBannedName {
  const DVBannedName({
    required this.name,
    required this.path,
    required this.line,
  });

  final String name;
  final String path;
  final int line;

  @override
  String toString() => '$path:$line declares $name, which the windowing '
      'contract names as never-existing. Make it private, or use DV.Window.';
}

/// Declarations the contract permits despite the ban, and why.
///
/// `DVWindowManager` is the type `DV.Platform.Window` returns. The contract
/// says "anything the implementation needs beyond DV.Window and DVWindow is
/// private", but Dart privacy is per *library*: a private class declared in
/// src/windowing/window.dart cannot be the return type of a member declared in
/// dartvel_flutter.dart. Making it private therefore does not compile, and the
/// clause cannot be satisfied as written without either merging those
/// libraries with `part` or giving the type a public name the contract has not
/// chosen.
///
/// Recorded here rather than dropped from the list, so the exception is
/// visible, attributable and removable -- and so the rule still catches a
/// *new* one.
const Map<String, String> dvBannedNameExceptions = <String, String>{
  'DVWindowManager':
      'returned by DV.Platform.Window; Dart per-library privacy prevents '
          'making it private without merging libraries or naming a public '
          'replacement. Open spec decision.',
};

/// Banned names *declared* in [source].
///
/// Declarations only. A comment saying the name does not exist -- the spec's
/// own sentence, and every doc comment repeating it -- must not trip the rule
/// that enforces it, or the rule becomes noise and gets switched off.
List<DVBannedName> dvFindBannedNames({
  required String path,
  required String source,
}) {
  final List<DVBannedName> found = <DVBannedName>[];
  final List<String> lines = source.split('\n');

  for (int i = 0; i < lines.length; i += 1) {
    final String line = lines[i];
    final String trimmed = line.trimLeft();
    if (trimmed.startsWith('//') || trimmed.startsWith('*') ||
        trimmed.startsWith('/*')) {
      continue;
    }

    for (final String banned in dvBannedPublicNames) {
      // A dotted name is a member path, not a declaration; it is banned as a
      // documented surface rather than as a class the analyzer would see.
      if (banned.contains('.')) continue;

      final RegExp declaration = RegExp(
        r'^\s*(?:abstract\s+|final\s+|sealed\s+|base\s+|interface\s+|mixin\s+)*'
        '(?:class|enum|extension|typedef|mixin)\\s+$banned\\b',
      );
      if (declaration.hasMatch(line)) {
        // An exception is still a violation of the stated rule; it is
        // recorded so the list stays honest, and skipped so the rule can
        // catch the next one instead of being switched off wholesale.
        if (dvBannedNameExceptions.containsKey(banned)) continue;
        found.add(DVBannedName(name: banned, path: path, line: i + 1));
      }
    }
  }
  return found;
}
