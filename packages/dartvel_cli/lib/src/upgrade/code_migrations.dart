/// The code rewrites behind `dartvel migrate-code`.
///
/// Upgrade and compatibility names them: `DVStyleModifier → DVModifier`,
/// `.styleModifier() → .modifier()` and `DV.Storage → DV.FileStorage`. The
/// list adds the other names the packages deprecate with an exact replacement
/// named in the deprecation, and nothing else: a rewrite is only safe when the
/// new name means the same thing, and a test holds every rule against the
/// declarations that ship.
///
/// The rewrite works on tokens, not on text. A regular expression over the
/// file would rewrite `DV.Storage` inside a string the program prints and
/// inside a comment that documents it, and both still compile, so nothing
/// would say the program changed. The scanner here knows Dart's comments
/// (nested block comments included), its strings (raw, triple-quoted, escaped)
/// and its interpolations, which are code and are rewritten.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// How a rule recognises its name among the tokens.
enum DVCodeMigrationMatch {
  /// Any identifier token with the name: a type, a constructor, a typedef.
  identifier,

  /// A method called through `.`, `?.`, `..` or `?..` and immediately
  /// invoked. A declaration of the same name, a named argument or a field of
  /// the application's own is left alone.
  invokedMember,

  /// The member of `DV`: the token after `DV .`.
  dvMember,

  /// An annotation: the token after `@`. The same name in a `show` clause is
  /// left, because the replacement is not a single name that can stand there.
  annotation,
}

/// One rewrite.
class DVCodeMigrationRule {
  const DVCodeMigrationRule({
    required this.id,
    required this.match,
    required this.from,
    required this.to,
    required this.evidence,
  });

  /// Stable, so output and tooling can refer to a rule.
  final String id;
  final DVCodeMigrationMatch match;

  /// The token that is replaced.
  final String from;

  /// What replaces it.
  final String to;

  /// A pattern the packages' own source matches: the deprecation that names
  /// [to], or the alias that makes the two the same. Checked by a test, so a
  /// rule cannot outlive the reason it is safe.
  final String evidence;

  String get summary => switch (match) {
    DVCodeMigrationMatch.identifier => '$from → $to',
    DVCodeMigrationMatch.invokedMember => '.$from() → .$to()',
    DVCodeMigrationMatch.dvMember => 'DV.$from → DV.$to',
    DVCodeMigrationMatch.annotation => '@$from → @$to',
  };
}

/// Every rule `dartvel migrate-code` applies, in the order they are listed.
const List<DVCodeMigrationRule> dvCodeMigrationRules = <DVCodeMigrationRule>[
  DVCodeMigrationRule(
    id: 'style-modifier-type',
    match: DVCodeMigrationMatch.identifier,
    from: 'DVStyleModifier',
    to: 'DVModifier',
    evidence: r'typedef DVStyleModifier = DVModifier;',
  ),
  DVCodeMigrationRule(
    id: 'style-modifier-method',
    match: DVCodeMigrationMatch.invokedMember,
    from: 'styleModifier',
    to: 'modifier',
    evidence:
        r'styleModifier\(DVModifier mod\) =>\s*(modifier\(mod\)|DVText\(text, mod\))',
  ),
  DVCodeMigrationRule(
    id: 'dv-storage',
    match: DVCodeMigrationMatch.dvMember,
    from: 'Storage',
    to: 'FileStorage',
    evidence:
        r"@Deprecated\('Use DV\.FileStorage\.[^)]*\)\s*static DVStorage get Storage",
  ),
  DVCodeMigrationRule(
    id: 'searchable-annotation',
    match: DVCodeMigrationMatch.annotation,
    from: 'DVSearchable',
    to: 'DVModel.searchableField',
    evidence:
        r"@Deprecated\('Use @DVModel\.searchableField\(\) instead\.[^)]*\)\s*class DVSearchable",
  ),
  DVCodeMigrationRule(
    id: 'sensitive-annotation',
    match: DVCodeMigrationMatch.annotation,
    from: 'DVSensitiveModelField',
    to: 'DVModel.sensitiveField',
    evidence:
        r"@Deprecated\('Use @DVModel\.sensitiveField\(\) instead\.[^)]*\)\s*class DVSensitiveModelField",
  ),
  DVCodeMigrationRule(
    id: 'debug-auth-provider',
    match: DVCodeMigrationMatch.identifier,
    from: 'DebugAuthProvider',
    to: 'LocalAuthProvider',
    evidence:
        r"@Deprecated\('Use LocalAuthProvider instead\.'\)\s*typedef DebugAuthProvider = LocalAuthProvider;",
  ),
  DVCodeMigrationRule(
    id: 'debug-analytics-provider',
    match: DVCodeMigrationMatch.identifier,
    from: 'DebugAnalyticsProvider',
    to: 'LocalAnalyticsProvider',
    evidence:
        r"@Deprecated\('Use LocalAnalyticsProvider instead\.'\)\s*typedef DebugAnalyticsProvider = LocalAnalyticsProvider;",
  ),
  DVCodeMigrationRule(
    id: 'debug-push-provider',
    match: DVCodeMigrationMatch.identifier,
    from: 'DebugPushNotificationProvider',
    to: 'LocalPushNotificationProvider',
    evidence:
        r"@Deprecated\('Use LocalPushNotificationProvider instead\.'\)\s*typedef DebugPushNotificationProvider = LocalPushNotificationProvider;",
  ),
];

/// One rewrite in one source.
class DVCodeRewrite {
  const DVCodeRewrite({
    required this.rule,
    required this.offset,
    required this.line,
    required this.column,
  });

  final DVCodeMigrationRule rule;

  /// Where the replaced token starts in the original source.
  final int offset;

  /// One-based, of the replaced token.
  final int line;
  final int column;
}

/// A source and what the rules made of it.
class DVSourceMigration {
  const DVSourceMigration(this.original, this.source, this.rewrites);

  final String original;
  final String source;
  final List<DVCodeRewrite> rewrites;
}

/// Applies [rules] to one Dart source.
DVSourceMigration dvMigrateDartSource(
  String source, {
  List<DVCodeMigrationRule> rules = dvCodeMigrationRules,
}) {
  final List<_Token> tokens = _DartScanner(source).scan();
  final List<(int, int, DVCodeMigrationRule)> edits =
      <(int, int, DVCodeMigrationRule)>[];

  String? text(int i) => i >= 0 && i < tokens.length ? tokens[i].text : null;

  for (int i = 0; i < tokens.length; i++) {
    final _Token token = tokens[i];
    if (!token.identifier) continue;
    for (final DVCodeMigrationRule rule in rules) {
      if (token.text != rule.from) continue;
      final bool matches = switch (rule.match) {
        DVCodeMigrationMatch.identifier => true,
        DVCodeMigrationMatch.invokedMember =>
          const <String>{'.', '?.', '..', '?..'}.contains(text(i - 1)) &&
              text(i + 1) == '(',
        DVCodeMigrationMatch.dvMember =>
          text(i - 1) == '.' && text(i - 2) == 'DV' && tokens[i - 2].identifier,
        DVCodeMigrationMatch.annotation =>
          text(i - 1) == '@' ||
              // `@prefix.DVSearchable`
              (text(i - 1) == '.' &&
                  text(i - 3) == '@' &&
                  (i >= 2 && tokens[i - 2].identifier)),
      };
      if (!matches) continue;
      edits.add((token.start, token.end, rule));
      break;
    }
  }

  if (edits.isEmpty) {
    return DVSourceMigration(source, source, const <DVCodeRewrite>[]);
  }

  final List<int> lineStarts = <int>[0];
  for (int i = 0; i < source.length; i++) {
    if (source.codeUnitAt(i) == 0x0A) lineStarts.add(i + 1);
  }
  (int, int) position(int offset) {
    int low = 0;
    int high = lineStarts.length - 1;
    while (low < high) {
      final int mid = (low + high + 1) >> 1;
      if (lineStarts[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return (low + 1, offset - lineStarts[low] + 1);
  }

  final StringBuffer out = StringBuffer();
  final List<DVCodeRewrite> rewrites = <DVCodeRewrite>[];
  int cursor = 0;
  for (final (int start, int end, DVCodeMigrationRule rule) in edits) {
    out
      ..write(source.substring(cursor, start))
      ..write(rule.to);
    cursor = end;
    final (int line, int column) = position(start);
    rewrites.add(
      DVCodeRewrite(rule: rule, offset: start, line: line, column: column),
    );
  }
  out.write(source.substring(cursor));
  return DVSourceMigration(source, out.toString(), rewrites);
}

/// What migrating a project would change.
class DVCodeMigrationPlan {
  const DVCodeMigrationPlan(this.root, this.files);

  final String root;

  /// Only the files with at least one rewrite, by forward-slash path relative
  /// to [root], sorted.
  final Map<String, DVSourceMigration> files;

  int get rewriteCount => files.values.fold(
    0,
    (int sum, DVSourceMigration m) => sum + m.rewrites.length,
  );

  bool get isEmpty => files.isEmpty;

  /// Rewrites per rule id, for a summary.
  Map<String, int> get countsByRule {
    final Map<String, int> counts = <String, int>{};
    for (final DVSourceMigration m in files.values) {
      for (final DVCodeRewrite r in m.rewrites) {
        counts[r.rule.id] = (counts[r.rule.id] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Every rewritten line, before and after, grouped by file.
  String render() {
    final StringBuffer out = StringBuffer();
    for (final MapEntry<String, DVSourceMigration> entry in files.entries) {
      final List<String> before = entry.value.original.split('\n');
      final List<String> after = entry.value.source.split('\n');
      final Set<int> shown = <int>{};
      for (final DVCodeRewrite r in entry.value.rewrites) {
        out.writeln(
          '${entry.key}:${r.line}:${r.column}  ${r.rule.summary}  '
          '[${r.rule.id}]',
        );
        // Rewrites never add or remove a line, so line n before is line n
        // after. A line with two rewrites is shown once.
        if (shown.add(r.line)) {
          out
            ..writeln('  - ${before[r.line - 1]}')
            ..writeln('  + ${after[r.line - 1]}');
        }
      }
    }
    return out.toString();
  }
}

/// Directories never read: tool caches, dependency installs, build output,
/// and the generated client, which the generator writes and rewrites itself.
const Set<String> _skippedDirectories = <String>{
  '.dart_tool',
  '.git',
  '.dartvel',
  'build',
  'node_modules',
  'dartvel_client',
};

/// Plans the rewrites for every Dart file under [root], writing nothing.
DVCodeMigrationPlan dvPlanCodeMigration(
  String root, {
  List<DVCodeMigrationRule> rules = dvCodeMigrationRules,
}) {
  final Directory project = Directory(root).absolute;
  final List<File> dartFiles = <File>[];
  void walk(Directory dir) {
    final List<FileSystemEntity> entries = dir.listSync(followLinks: false)
      ..sort(
        (FileSystemEntity a, FileSystemEntity b) => a.path.compareTo(b.path),
      );
    for (final FileSystemEntity entity in entries) {
      final String name = p.basename(entity.path);
      if (entity is Directory) {
        if (!_skippedDirectories.contains(name)) walk(entity);
      } else if (entity is File && name.endsWith('.dart')) {
        dartFiles.add(entity);
      }
    }
  }

  if (project.existsSync()) walk(project);
  final Map<String, DVSourceMigration> files = <String, DVSourceMigration>{};
  for (final File file in dartFiles) {
    final String source;
    try {
      source = file.readAsStringSync();
    } on FileSystemException {
      continue;
    } on FormatException {
      // Not UTF-8, so not a Dart library the analyzer would read either.
      continue;
    }
    final DVSourceMigration migration = dvMigrateDartSource(
      source,
      rules: rules,
    );
    if (migration.rewrites.isEmpty) continue;
    files[p.relative(file.path, from: project.path).replaceAll(r'\', '/')] =
        migration;
  }
  return DVCodeMigrationPlan(project.path, files);
}

/// What applying a plan did.
class DVCodeMigrationApplyResult {
  const DVCodeMigrationApplyResult({required this.applied, this.message});

  final bool applied;
  final String? message;
}

/// Writes [plan], or nothing at all.
///
/// Every file is checked against what was planned before any is written: a
/// file edited since the plan was shown would have its edit replaced by a
/// rewrite of the old text, and a project with half its files migrated is a
/// state nobody chose. Each file is replaced by one rename.
DVCodeMigrationApplyResult dvApplyCodeMigration(DVCodeMigrationPlan plan) {
  final List<String> changed = <String>[
    for (final MapEntry<String, DVSourceMigration> entry in plan.files.entries)
      if (!_unchanged(File(p.join(plan.root, entry.key)), entry.value.original))
        entry.key,
  ];
  if (changed.isNotEmpty) {
    return DVCodeMigrationApplyResult(
      applied: false,
      message:
          'Changed since the plan was made, so nothing was written: '
          '${changed.join(', ')}. Run migrate-code again.',
    );
  }
  for (final MapEntry<String, DVSourceMigration> entry in plan.files.entries) {
    final File target = File(p.join(plan.root, entry.key));
    final File staged = File('${target.path}.dartvel-migrate')
      ..writeAsStringSync(entry.value.source, flush: true);
    staged.renameSync(target.path);
  }
  return const DVCodeMigrationApplyResult(applied: true);
}

bool _unchanged(File file, String expected) {
  try {
    return file.readAsStringSync() == expected;
  } on Object {
    return false;
  }
}

/// A token of Dart code. Comments, whitespace and string text are not tokens;
/// the code inside an interpolation is.
class _Token {
  const _Token(this.start, this.end, this.text, {required this.identifier});

  final int start;
  final int end;
  final String text;
  final bool identifier;
}

class _DartScanner {
  _DartScanner(this.src);

  final String src;
  final List<_Token> tokens = <_Token>[];
  int i = 0;

  List<_Token> scan() {
    _code(untilBrace: false);
    return tokens;
  }

  int _at(int index) => index < src.length ? src.codeUnitAt(index) : -1;

  static bool _identStart(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      c == 0x24;

  static bool _identPart(int c) => _identStart(c) || (c >= 0x30 && c <= 0x39);

  static bool _quote(int c) => c == 0x27 || c == 0x22;

  /// Scans code until the end of the source or, inside an interpolation, the
  /// brace that closes it (consumed).
  void _code({required bool untilBrace}) {
    int depth = 0;
    while (i < src.length) {
      final int c = src.codeUnitAt(i);
      if (c == 0x2F && _at(i + 1) == 0x2F) {
        while (i < src.length && src.codeUnitAt(i) != 0x0A) {
          i++;
        }
      } else if (c == 0x2F && _at(i + 1) == 0x2A) {
        _blockComment();
      } else if (_quote(c)) {
        _string(raw: false);
      } else if ((c == 0x72 || c == 0x52) &&
          _quote(_at(i + 1)) &&
          (i == 0 || !_identPart(src.codeUnitAt(i - 1)))) {
        i++;
        _string(raw: true);
      } else if (_identStart(c)) {
        final int start = i;
        while (i < src.length && _identPart(src.codeUnitAt(i))) {
          i++;
        }
        tokens.add(_Token(start, i, src.substring(start, i), identifier: true));
      } else if (c >= 0x30 && c <= 0x39) {
        while (i < src.length &&
            (_identPart(src.codeUnitAt(i)) || src.codeUnitAt(i) == 0x2E) &&
            !(src.codeUnitAt(i) == 0x2E && !_digit(_at(i + 1)))) {
          i++;
        }
      } else if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        i++;
      } else {
        final int start = i;
        String punct = String.fromCharCode(c);
        if (c == 0x3F &&
            src.startsWith('?..', i) &&
            !src.startsWith('?...', i)) {
          punct = '?..';
        } else if (c == 0x3F && _at(i + 1) == 0x2E) {
          punct = '?.';
        } else if (src.startsWith('...', i)) {
          punct = '...';
        } else if (src.startsWith('..', i)) {
          punct = '..';
        }
        i += punct.length;
        if (c == 0x7B) depth++;
        if (c == 0x7D) {
          if (untilBrace && depth == 0) return;
          depth--;
        }
        tokens.add(_Token(start, i, punct, identifier: false));
      }
    }
  }

  static bool _digit(int c) => c >= 0x30 && c <= 0x39;

  void _blockComment() {
    int depth = 0;
    while (i < src.length) {
      if (src.startsWith('/*', i)) {
        depth++;
        i += 2;
      } else if (src.startsWith('*/', i)) {
        depth--;
        i += 2;
        if (depth == 0) return;
      } else {
        i++;
      }
    }
  }

  /// At an opening quote.
  void _string({required bool raw}) {
    final int q = src.codeUnitAt(i);
    final bool triple = _at(i + 1) == q && _at(i + 2) == q;
    i += triple ? 3 : 1;
    while (i < src.length) {
      final int c = src.codeUnitAt(i);
      if (c == q && (!triple || (_at(i + 1) == q && _at(i + 2) == q))) {
        i += triple ? 3 : 1;
        return;
      }
      if (!triple && c == 0x0A) return; // unterminated; recover at the line
      if (!raw && c == 0x5C) {
        i += 2;
      } else if (!raw && c == 0x24 && _at(i + 1) == 0x7B) {
        i += 2;
        _code(untilBrace: true);
      } else if (!raw &&
          c == 0x24 &&
          _identStart(_at(i + 1)) &&
          _at(i + 1) != 0x24) {
        final int start = ++i;
        while (i < src.length &&
            _identPart(src.codeUnitAt(i)) &&
            src.codeUnitAt(i) != 0x24) {
          i++;
        }
        tokens.add(_Token(start, i, src.substring(start, i), identifier: true));
      } else {
        i++;
      }
    }
  }
}
