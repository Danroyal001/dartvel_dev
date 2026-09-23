/// The security documents' citations, and whether the tree still has them.
///
/// `SECURITY.md`, `docs/security/secure-development.md`,
/// `docs/security/compliance-plan.md` and the secure-development skill all
/// name files: this is where the password hasher lives, this is the filter
/// deciding what reaches a browser, this is the middleware that puts headers
/// on a response. Naming them is what makes the documents usable rather than
/// a wall of intentions, and it is also how they rot. A file is renamed and
/// the policy that was accurate starts sending its next reader somewhere
/// that does not exist.
///
/// So the citations are checked, the way `docs/spec-status.json` is. A
/// backticked path under one of this repository's top-level directories has
/// to be there, and so does every document a link points at.
///
/// Imports only `dart:` libraries, so it runs as `dart tool/ci/...` with no
/// package resolution.
library;

import 'dart:io';

/// The documents this checks.
const List<String> dvSecurityDocuments = <String>[
  'SECURITY.md',
  'docs/security/secure-development.md',
  'docs/security/compliance-plan.md',
  '.claude/skills/secure-development/SKILL.md',
];

/// Where a citation can start. A backticked string beginning with one of
/// these is a path; anything else in backticks is an identifier, a header
/// name or a shell word, and this has no business guessing about it.
const List<String> _roots = <String>[
  'packages/',
  'tool/',
  'docs/',
  'sites/',
  'examples/',
  'lib/',
  'test/',
  '.github/',
  '.claude/',
];

/// A path in backticks: `packages/dartvel_core/lib/src/auth/password.dart`.
final RegExp _backticked = RegExp(r'`([^`\n]+)`');

/// A markdown link: [text](target).
final RegExp _link = RegExp(r'\[[^\]\n]*\]\(([^)\s]+)\)');

/// A fenced block, whose contents are commands and sample code.
final RegExp _fence = RegExp(r'^```.*?^```', multiLine: true, dotAll: true);

/// Every repository path [markdown] cites, without repeats.
///
/// [from] is the document's own path, which is what a relative link resolves
/// against: `compliance-plan.md` in `docs/security/secure-development.md` is
/// `docs/security/compliance-plan.md`, and the same word in a document at the
/// root is something else entirely.
List<String> dvCitedPaths(String markdown, {String from = ''}) {
  final String prose = markdown.replaceAll(_fence, '');
  final Set<String> found = <String>{};

  for (final RegExpMatch match in _backticked.allMatches(prose)) {
    final String text = match.group(1)!.trim();
    if (text.contains(' ')) continue;
    if (!_roots.any(text.startsWith)) continue;
    found.add(text);
  }

  for (final RegExpMatch match in _link.allMatches(prose)) {
    final String target = match.group(1)!.trim();
    if (target.startsWith('#')) continue;
    if (target.contains('://') || target.startsWith('mailto:')) continue;
    found.add(_resolve(target.split('#').first, from));
  }

  return found.toList()..sort();
}

/// [target], written in the document at [from], as a repository path.
String _resolve(String target, String from) {
  if (target.startsWith('/')) return target.substring(1);
  final List<String> parts = from.split('/')
    ..removeLast(); // the document itself
  for (final String segment in target.split('/')) {
    if (segment == '.' || segment.isEmpty) continue;
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(segment);
  }
  return parts.join('/');
}

/// Whether [path] is a file or a directory in this repository.
///
/// A trailing slash means a directory was meant, and a directory that is now
/// a file is as broken a citation as one that is nothing at all.
bool dvExists(String path, {String root = '.'}) {
  final String full = '$root/$path';
  if (path.endsWith('/')) return Directory(full).existsSync();
  return File(full).existsSync() || Directory(full).existsSync();
}

/// Every citation in [documents] that names nothing, as `document -> path`.
List<String> dvMissingCitations({
  String root = '.',
  List<String> documents = dvSecurityDocuments,
}) {
  final List<String> missing = <String>[];
  for (final String document in documents) {
    final File file = File('$root/$document');
    if (!file.existsSync()) {
      missing.add('$document -> the document itself is missing');
      continue;
    }
    for (final String cited
        in dvCitedPaths(file.readAsStringSync(), from: document)) {
      if (!dvExists(cited, root: root)) missing.add('$document -> $cited');
    }
  }
  return missing;
}
