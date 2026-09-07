/// Evidence that nothing calls.
///
/// `tool/spec_status_check.dart` holds a section's claim to the files it
/// cites and checks that they exist. Existing is a low bar, and three
/// findings in one audit cleared it while doing nothing at all:
///
///   * `@DVPage(policy:)` had a guard builder, a runtime checker, and a unit
///     test for each. No caller. The index said the router called them.
///   * `DVScheduler` evaluates cron entries. Nothing instantiates it, and
///     the section's own note says it runs them.
///   * The lifecycle setters are called only from their own tests, so four
///     of six signals never change for the life of an application.
///
/// All three are one mistake: a correct implementation written in isolation,
/// unit-tested against its own return value, recorded as shipped, and never
/// wired. A test asserting on the shape of a string returned by a function
/// nothing calls passes forever.
///
/// So this asks a different question. Not whether the file exists -- whether
/// anything outside a test calls what it declares.
library;

import 'dart:convert';
import 'dart:io';

/// The public top-level symbols [source] declares.
///
/// Deliberately shallow: a regular expression over declarations rather than
/// a parse. The point is to have a name to look for, and a name this misses
/// is a check that stays quiet rather than one that lies.
Set<String> dvPublicSymbols(String source) {
  final Set<String> found = <String>{};
  for (final String raw in const LineSplitter().convert(source)) {
    final String line = raw.trimLeft();
    // Comments quote the API constantly in this repository, and a symbol
    // inside one is not a declaration.
    if (line.startsWith('//') || line.startsWith('///')) continue;

    final RegExpMatch? type = RegExp(
      r'^(?:abstract\s+|final\s+|sealed\s+|base\s+|interface\s+)*'
      r'(?:class|mixin|enum|extension|typedef)\s+([A-Z][A-Za-z0-9_]*)',
    ).firstMatch(line);
    if (type != null) {
      found.add(type.group(1)!);
      continue;
    }

    // A top-level constant or a function, both of which this repository
    // names with a dv prefix by convention.
    final RegExpMatch? member = RegExp(
      r'^(?:const|final)?\s*[A-Za-z_][A-Za-z0-9_<>?,\s]*\s+'
      r'(dv[A-Z][A-Za-z0-9_]*)\s*[=(]',
    ).firstMatch(line);
    if (member != null) found.add(member.group(1)!);
  }
  return found;
}

/// The evidence files nothing outside a test refers to.
///
/// [symbolsByFile] is what each cited implementation file declares.
/// [referencesByLibFile] is every name mentioned by every other
/// implementation file. A file is reachable when one of its symbols appears
/// in another file -- one is enough, because this is looking for files
/// nothing reaches at all rather than for dead members inside a live file.
///
/// A file referring to itself does not count: `dvPageGuardChain` calling
/// `dvPagePolicyGuard` is not a caller, it is the same island.
List<String> dvUnreachableEvidence({
  required Map<String, Set<String>> symbolsByFile,
  required Map<String, Set<String>> referencesByLibFile,
}) {
  final List<String> unreachable = <String>[];
  for (final MapEntry<String, Set<String>> file in symbolsByFile.entries) {
    // Nothing public to call, so nothing to be unreachable. Reporting it
    // would be noise, and noise teaches people to ignore the check.
    if (file.value.isEmpty) continue;

    bool reached = false;
    for (final MapEntry<String, Set<String>> other
        in referencesByLibFile.entries) {
      if (other.key == file.key) continue;
      if (other.value.any(file.value.contains)) {
        reached = true;
        break;
      }
    }
    if (!reached) unreachable.add(file.key);
  }
  return unreachable;
}

/// Every file reachable by following `export` from [barrels].
///
/// A cited file can be called by nobody in this repository and still be
/// exactly right: `DVRedisQueueAdapter` is constructed by the application
/// and handed to the framework, so the caller lives in somebody else's
/// project. What decides whether that is fine is whether an application can
/// import it at all, and the answer is the package's public barrel.
///
/// Exports chain -- `dartvel.dart` exports `observability.dart`, which
/// exports `tracing_middleware.dart` -- so following one level would call a
/// reachable file unreachable. `package:` exports point outside this
/// package and are somebody else's problem.
Set<String> dvExportedFiles({
  required Iterable<String> barrels,
  required Map<String, String> sourceByFile,
}) {
  final Set<String> seen = <String>{};
  final List<String> pending = <String>[...barrels];

  while (pending.isNotEmpty) {
    final String current = pending.removeLast();
    if (!seen.add(current)) continue;
    final String? source = sourceByFile[current];
    if (source == null) continue;

    // The whole directive, not its first path. A conditional export names
    // several files -- `export 'stub.dart' if (dart.library.io) 'io.dart';`
    // is how anything needing sockets ships here -- and reading only the
    // first calls the real implementation unreachable. That is every
    // database, cache, mail and LDAP client in the package, and the reason
    // it went unnoticed is that the stub declares the same names, so the
    // symbols looked reached from somewhere else.
    for (final RegExpMatch directive in RegExp(
      r'^\s*export\s+[^;]+;',
      multiLine: true,
    ).allMatches(source)) {
      for (final RegExpMatch m
          in RegExp('''['"]([^'"]+)['"]''').allMatches(directive.group(0)!)) {
        final String target = m.group(1)!;
        if (target.startsWith('dart:') || target.startsWith('package:')) {
          continue;
        }
        // A condition names a library, not a file: `dart.library.io` has no
        // quotes around it, so only the paths reach here.
        pending.add(_dvResolve(current, target));
      }
    }
  }
  return seen;
}

/// `lib/src/o/observability.dart` + `tracing_middleware.dart`.
String _dvResolve(String from, String relative) {
  final List<String> base = from.split('/')..removeLast();
  for (final String part in relative.split('/')) {
    if (part == '.' || part.isEmpty) continue;
    if (part == '..') {
      if (base.isNotEmpty) base.removeLast();
      continue;
    }
    base.add(part);
  }
  return base.join('/');
}

/// Cited files split by who could possibly be calling them.
class DVEvidenceReach {
  const DVEvidenceReach({
    required this.unreachable,
    required this.applicationOnly,
  });

  /// Nothing in this repository names it and no application can import it.
  /// There is no caller anywhere, which is the case worth failing a build
  /// over.
  final List<String> unreachable;

  /// Exported for an application to call, and called by nothing here. Right
  /// for an adapter, wrong for a checker the framework was supposed to
  /// invoke -- so it is reported rather than failed on.
  final List<String> applicationOnly;
}

/// Which cited files have a caller, and which only could have one.
DVEvidenceReach dvEvidenceReach({
  required Map<String, Set<String>> symbolsByFile,
  required Map<String, Set<String>> referencesByLibFile,
  required Set<String> exportedFiles,
}) {
  final List<String> unreachable = <String>[];
  final List<String> applicationOnly = <String>[];

  for (final String path in dvUnreachableEvidence(
    symbolsByFile: symbolsByFile,
    referencesByLibFile: referencesByLibFile,
  )) {
    if (exportedFiles.contains(path)) {
      applicationOnly.add(path);
    } else {
      unreachable.add(path);
    }
  }

  return DVEvidenceReach(
    unreachable: unreachable,
    applicationOnly: applicationOnly,
  );
}
