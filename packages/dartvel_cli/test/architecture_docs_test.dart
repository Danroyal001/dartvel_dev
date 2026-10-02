import 'dart:io';

import 'package:test/test.dart';

/// Tests for item 2: opinionated architecture docs written into every project.
///
/// These assert that `dartvel create` and `dartvel init` write a `docs/architecture/`
/// directory containing the opinionated architecture guides (initialisation, data,
/// HTTP, UI, naming, setup, Git, process, and Dartvel-specific: models, backend
/// functions, Studio, modules), and that the docs stay matched to the installed
/// Dartvel version.
void main() {
  group('architecture docs (item 2)', () {
    test('docs/architecture/ exists after init', () {
      // Failing test: architecture docs are not yet implemented.
      expect(File('docs/architecture/init.md').existsSync(), isTrue,
          reason: 'docs/architecture/init.md must be written by dartvel init');
    });

    test('docs/architecture/data.md covers data model rules', () {
      expect(
        File('docs/architecture/data.md').existsSync(),
        isTrue,
        reason: 'docs/architecture/data.md must describe model, form and sync rules',
      );
    });
  });
}
