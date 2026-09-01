import 'package:args/command_runner.dart';
import 'package:dartvel_core/dartvel.dart';

import '../utils/logger.dart';

/// Renders the explanation for [arguments], as the command would print it.
///
/// Separated from the command so it can be tested without running a
/// CommandRunner or capturing stdout.
String dvExplain(List<String> arguments) {
  final String query = arguments.isEmpty ? '' : arguments.first.trim();

  if (query.isEmpty) {
    // Orient rather than dump: the full list is 23 rows and growing, and
    // someone who typed the bare command usually wants to know what exists.
    final StringBuffer out = StringBuffer()
      ..writeln('Dartvel diagnostic codes.')
      ..writeln();
    for (final String family in DVDiagnostics.families()) {
      final int count = DVDiagnostics.family(family).length;
      out.writeln('  $family  ($count codes)');
    }
    return (out
          ..writeln()
          ..writeln('Try: dartvel explain DV-WINDOW-004')
          ..write('     dartvel explain DV-WINDOW'))
        .toString();
  }

  final DVDiagnostic? found = DVDiagnostics.find(query);
  if (found != null) {
    return '${found.code}  [${found.level}]\n\n  ${found.reason}';
  }

  // A family name lists the family.
  final List<DVDiagnostic> family = DVDiagnostics.family(query);
  if (family.isNotEmpty) {
    final StringBuffer out = StringBuffer()
      ..writeln('${query.toUpperCase()} — ${family.length} codes')
      ..writeln();
    for (final DVDiagnostic entry in family) {
      out.writeln('  ${entry.code}  [${entry.level}]  ${entry.reason}');
    }
    return out.toString().trimRight();
  }

  // Printing nothing here reads like the command failed, so say what was not
  // found and show the family it looks like it belongs to.
  final StringBuffer out = StringBuffer()
    ..writeln('"$query" is not a known Dartvel diagnostic code.');
  final int dash = query.lastIndexOf('-');
  final List<DVDiagnostic> guess =
      dash > 0 ? DVDiagnostics.family(query.substring(0, dash)) : const [];
  if (guess.isNotEmpty) {
    out
      ..writeln()
      ..writeln('Codes in that family:');
    for (final DVDiagnostic entry in guess) {
      out.writeln('  ${entry.code}  [${entry.level}]  ${entry.reason}');
    }
  } else {
    out
      ..writeln()
      ..writeln('Families: ${DVDiagnostics.families().join(', ')}');
  }
  return out.toString().trimRight();
}

/// Looks up a diagnostic code the runtime emitted.
class ExplainCommand extends Command<void> {
  @override
  final String name = 'explain';

  @override
  final String description =
      'Explain a Dartvel diagnostic code, e.g. dartvel explain DV-WINDOW-004.';

  @override
  final String invocation = 'dartvel explain [DV-WINDOW-004 | DV-WINDOW]';

  @override
  Future<void> run() async {
    Logger.log(dvExplain(argResults?.rest ?? const <String>[]));
  }
}
