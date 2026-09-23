/// Fails when a security document cites a path this repository does not have.
///
///     dart tool/ci/security_docs_check.dart
///
/// The documents are worth reading because they name files. That is also
/// what makes them rot: rename one file and a policy starts sending its next
/// reader somewhere that does not exist. The reasoning, and what counts as a
/// citation, is in `tool/ci/security_docs.dart`.
library;

import 'dart:io';

import 'security_docs.dart';

void main() {
  final List<String> missing = dvMissingCitations();
  for (final String problem in missing) {
    stdout.writeln('::error::$problem');
  }
  if (missing.isEmpty) {
    stdout.writeln('security documents: every citation is in the tree');
    return;
  }
  stdout.writeln('${missing.length} citation(s) name nothing. Fix the '
      'document or put the file back.');
  exitCode = 1;
}
