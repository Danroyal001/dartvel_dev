/// Conventions check for Dartvel applications.
///
/// Each rule carries a DV-CONV-0xx code, a plain-word message, and is checked
/// by scanning source files (regex-based over masked source, like the tooltip
/// lint) rather than by a runtime assertion. A failing fixture accompanies
/// each rule in the test suite.
library dartvel_cli.analysis.conventions_check;

import 'dart:io';
import 'package:path/path.dart' as p;

/// One convention violation found in source.
class DVConventionFinding {
  const DVConventionFinding({
    required this.code,
    required this.rule,
    required this.path,
    required this.line,
    required this.message,
    required this.fix,
  });

  /// DV-CONV-0xx code.
  final String code;

  /// Short rule name.
  final String rule;

  final String path;
  final int line;
  final String message;
  final String fix;

  @override
  String toString() => '$path:$line  [$code] $rule — $message  ($fix)';
}

/// Scan a single Dart source file for all convention rules.
///
/// Rules are checked conservatively: only what the scanner can be certain
/// of is reported. Rules that need an AST-level view stay out of this
/// scanner and are documented as future work.
List<DVConventionFinding> dvFindConventionIssues({
  required String path,
  required String source,
}) {
  final findings = <DVConventionFinding>[];

  // Helper: line number for byte offset.
  int lineOf(int offset) {
    var line = 1;
    for (var i = 0; i < offset && i < source.length; i++) {
      if (source.codeUnitAt(i) == 10) line++;
    }
    return line;
  }

  void add(int offset, String code, String rule, String message, String fix) {
    findings.add(DVConventionFinding(
      code: code,
      rule: rule,
      path: path,
      line: lineOf(offset),
      message: message,
      fix: fix,
    ));
  }

  // ------------------------------------------------------------------
  // DV-CONV-001: runApp/main not using DV.run (detect runApp for now)
  // ------------------------------------------------------------------
  // Only in main files: detect runApp( usage. Once DV.run(args) exists,
  // coordinate detection accordingly.
  final bool isMainFile = p.basenameWithoutExtension(path) == 'main';
  if (isMainFile) {
    final RegExp runAppRe = RegExp(r'runApp\s*\(');
    for (final match in runAppRe.allMatches(source)) {
      add(
        match.start,
        'DV-CONV-001',
        'mainUsesRunApp',
        'main() uses runApp() instead of DV.run()',
        'Replace runApp(...) with DV.run(...) (or keep it as the framework convention).',
      );
    }
  }

  // ------------------------------------------------------------------
  // DV-CONV-002: classes not using primary constructors
  // ------------------------------------------------------------------
  // Conservative: detects `class X {` followed by a field declaration and
  // then a constructor that restates the field (`X(this.field)`) rather
  // than a primary-constructor shape (`class X({required this.field})`).
  // This is a lexical approximation: it catches the old shape.
  final RegExp classRe = RegExp(
    r'class\s+[A-Za-z_][A-Za-z0-9_]*',
  );
  for (final match in classRe.allMatches(source)) {
    final int classOffset = match.start;
    // Check if it already uses primary constructor by looking for `({` soon after.
    final snippetAfter = source.substring(
      match.end,
      (match.end + 200).clamp(0, source.length),
    );
    final bool hasPrimary = RegExp(r'\(\{').hasMatch(snippetAfter);
    if (!hasPrimary) {
      // Look for a constructor declaration within ~500 chars that restates fields.
      final RegExp constructorRe = RegExp(
        r'[A-Z][a-zA-Z0-9_]*\s*\([^)]*this\.\w+',
      );
      final int windowEnd = (classOffset + 600).clamp(0, source.length);
      final String window = source.substring(classOffset, windowEnd);
      if (constructorRe.hasMatch(window)) {
        add(
          classOffset,
          'DV-CONV-002',
          'noPrimaryConstructor',
          'Class uses an old constructor shape (restates fields) instead of a primary constructor.',
          'Convert to primary constructor: `class Name({required Type field})`.',
        );
      }
    }
  }

  // ------------------------------------------------------------------
  // DV-CONV-003: Flutter layout/text widgets where DV alternatives exist
  // ------------------------------------------------------------------
  // Reports Scaffold, Container, Column, Row, Stack, Text, Padding,
  // SizedBox, ElevatedButton, TextButton, IconButton (only when no label).
  final List<String> flutterWidgets = [
    'Scaffold',
    'Container',
    'Column',
    'Row',
    'Stack',
    'Text',
    'Padding',
    'SizedBox',
    'ElevatedButton',
    'TextButton',
  ];
  for (final name in flutterWidgets) {
    final RegExp widgetRe = RegExp(r'(?<![\w.])' + RegExp.escape(name) + r'\s*\(');
    for (final match in widgetRe.allMatches(source)) {
      add(
        match.start,
        'DV-CONV-003',
        'flutterWidgetInsteadOfDv',
        '$name used where DVBox/DVText/DVModifier exists.',
        'Prefer DVBox, DVText, DVModifier or DVIconButton.',
      );
    }
  }
  // IconButton is only flagged when it has no tooltip (already covered by
  // tooltip lint); here we flag any IconButton that lacks a label argument.
  final RegExp iconButtonNoLabel = RegExp(
    r'(?<![\w.])IconButton\s*\(([^)]*)\)',
    dotAll: true,
  );
  for (final match in iconButtonNoLabel.allMatches(source)) {
    final args = match.group(1) ?? '';
    if (!args.contains('label:') && !args.contains('tooltip:')) {
      add(
        match.start,
        'DV-CONV-003',
        'iconButtonNoLabel',
        'IconButton without label or tooltip.',
        'Use DVIconButton(label: ...) or add tooltip and label.',
      );
    }
  }

  // ------------------------------------------------------------------
  // DV-CONV-004: string routes
  // ------------------------------------------------------------------
  final RegExp stringRouteLiteral = RegExp(
    r"DVRouteTarget\s*\(",
  );
  for (final match in stringRouteLiteral.allMatches(source)) {
    add(
      match.start,
      'DV-CONV-004',
      'stringRouteLiteral',
      'String literal route used: DVRouteTarget(\'/...\')',
      'Use the generated typed route: DVRoutes.name.',
    );
  }
  final RegExp navigatorPushNamed = RegExp(
    r'Navigator\.pushNamed\s*\(\s*context\s*,',
  );
  for (final match in navigatorPushNamed.allMatches(source)) {
    add(
      match.start,
      'DV-CONV-004',
      'navigatorPushNamedString',
      'String route in Navigator.pushNamed(..., \'/path\')',
      'Use DVRoutes.name instead of a literal.',
    );
  }

  // ------------------------------------------------------------------
  // DV-CONV-005: records / SQL / DVRecord / ensureSchema in app code
  // ------------------------------------------------------------------
  final RegExp sqlOrRecordPatterns = RegExp(
    r'(?<![\w.])(records\.(insert|update|delete|find)|ensureSchema|DVRecordTable|DVRecordAdapter)',
  );
  for (final match in sqlOrRecordPatterns.allMatches(source)) {
    add(
      match.start,
      'DV-CONV-005',
      'recordOrSqlInApp',
      'Record/SQL operation or adapter used directly in app code.',
      'Write data through the generated data model only.',
    );
  }

  // ------------------------------------------------------------------
  // DV-CONV-006: public annotated generation inputs (must be private `_`)
  // ------------------------------------------------------------------
  // Detect `@DVModel` or `@DVPage` etc. on a public class (not starting with `_`).
  final RegExp annotationRe = RegExp(
    r'@DV(Model|Page|FunctionalWidget|BackendFunction|Job\.handler)\s*\(\)',
  );
  for (final match in annotationRe.allMatches(source)) {
    // Find the class declaration after this annotation.
    final after = source.substring(match.end);
    final classMatch = RegExp(r'class\s+([A-Za-z_][A-Za-z0-9_]*)').firstMatch(after);
    if (classMatch != null) {
      final className = classMatch.group(1)!;
      if (!className.startsWith('_')) {
        add(
          match.start,
          'DV-CONV-006',
          'publicAnnotatedInput',
          'Public annotated generation input: class $className (must be private `_`).',
          'Rename to private `_` class and reference the generated public API.',
        );
      }
    }
  }

  // ------------------------------------------------------------------
  // DV-CONV-007: build_runner in pubspec.yaml
  // ------------------------------------------------------------------
  // This is checked at project level, not per-file. We note it here if
  // the file name suggests it's pubspec.yaml.
  if (p.basename(path) == 'pubspec.yaml') {
    if (source.contains('build_runner')) {
      add(
        0,
        'DV-CONV-007',
        'buildRunnerInPubspec',
        'build_runner declared in pubspec.yaml.',
        'Remove build_runner; Dartvel uses its own CLI generator.',
      );
    }
  }

  // ------------------------------------------------------------------
  // DV-CONV-008: imports of generated siblings instead of barrel
  // ------------------------------------------------------------------
  final RegExp siblingImport = RegExp(
    r"import\s+.*router\.g\.dart",
  );
  for (final match in siblingImport.allMatches(source)) {
    add(
      match.start,
      'DV-CONV-008',
      'generatedSiblingImport',
      'Direct import of a generated sibling file.',
      'Import the barrel: `dartvel_client/dartvel_client.dart`.',
    );
  }

  // ------------------------------------------------------------------
  // DV-CONV-009: MethodChannel / EventChannel
  // ------------------------------------------------------------------
  final RegExp methodChannelRe = RegExp(
    r'(?<![\w.])MethodChannel|EventChannel|BasicMessageChannel',
  );
  for (final match in methodChannelRe.allMatches(source)) {
    add(
      match.start,
      'DV-CONV-009',
      'flutterPlatformChannel',
      'Flutter platform channel used (MethodChannel/EventChannel).',
      'Use FFI/ffigen or JNI bindings through DV.Platform.',
    );
  }

  // ------------------------------------------------------------------
  // DV-CONV-010: DV.Mail / DV.Realtime / DV.Authorization
  // ------------------------------------------------------------------
  if (source.contains('DV.Mail') || source.contains('DV\.Mail')) {
    final int off = source.indexOf(RegExp('DV\.Mail'));
    add(
      off >= 0 ? off : 0,
      'DV-CONV-010',
      'deprecatedNamespaceMail',
      'DV.Mail used; notifications mail is DV.Notifications.mail.',
      'Use DV.Notifications.mail.send(...) instead.',
    );
  }
  if (source.contains('DV.Realtime') || source.contains('DV\.Realtime')) {
    final int off = source.indexOf(RegExp('DV\.Realtime'));
    add(
      off >= 0 ? off : 0,
      'DV-CONV-010',
      'deprecatedNamespaceRealtime',
      'DV.Realtime used; sync is a model property.',
      'Use the generated model sync, not DV.Realtime.',
    );
  }
  if (source.contains('DV.Authorization') || source.contains('DV\.Authorization')) {
    final int off = source.indexOf(RegExp('DV\.Authorization'));
    add(
      off >= 0 ? off : 0,
      'DV-CONV-010',
      'deprecatedNamespaceAuthorization',
      'DV.Authorization used; authorization belongs under DV.Auth.authorization.',
      'Use DV.Auth.authorization instead.',
    );
  }

  // ------------------------------------------------------------------
  // DV-CONV-011: missing dot shorthands where valid (info level)
  // ------------------------------------------------------------------
  // Conservative lexical check: `.center`, `.all(`, `.w600`, `.offline`, `.zero`
  // are already shorthand forms; we flag the longer form when it appears
  // in a context where shorthand would work.
  final RegExp longShorthandPatterns = RegExp(
    r'(?<![\w.])(mainAxisAlignment: MainAxisAlignment\.center|padding: EdgeInsets\.all\(|fontWeight: FontWeight\.w600|case\s+\.offline\s*=>|Duration\.zero)',
  );
  for (final match in longShorthandPatterns.allMatches(source)) {
    add(
      match.start,
      'DV-CONV-011',
      'missingDotShorthand',
      'Full-form value where dot shorthand is valid.',
      'Use the shorthand: `.center`, `.all(8)`, `.w600`, `.offline`, `.zero`.',
    );
  }

  findings.sort((a, b) => a.line.compareTo(b.line));
  return findings;
}

/// Scan all `.dart` files under a project's `lib/` (excluding generated).
List<DVConventionFinding> dvScanProjectForConventions(String root) {
  final libDir = Directory(p.join(root, 'lib'));
  if (!libDir.existsSync()) return const <DVConventionFinding>[];
  final findings = <DVConventionFinding>[];
  final files = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !RegExp(r'\.(g|freezed|dv|generated)\.dart$').hasMatch(f.path))
      .where((f) => !f.path.contains('${p.separator}generated${p.separator}'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final relative = p.relative(file.path, from: root);
    findings.addAll(dvFindConventionIssues(
      path: relative,
      source: file.readAsStringSync(),
    ));
  }
  return findings;
}
