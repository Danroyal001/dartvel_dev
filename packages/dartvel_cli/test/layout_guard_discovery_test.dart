// Layout and guard discovery had no test at all, which a mistake proved: a
// glob pattern was briefly turned into a literal `$pagesDir/**/_layout.dart`
// by an escaping slip, so nothing matched — and the entire suite still passed.
//
// A generator that finds nothing does not fail. It emits a smaller file, and
// the application loses its layouts without a single error.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:test/test.dart';

Future<Directory> _project(Map<String, String> files) async {
  final root = await Directory.systemTemp.createTemp('dartvel_layouts_');
  files.forEach((relative, contents) {
    final file = File('${root.path}/$relative');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  });
  File('${root.path}/pubspec.yaml').writeAsStringSync('name: shop\n');
  return root;
}

void main() {
  rootGuardTests();

  group('layout and guard discovery', () {
    test('finds a nested layout and a guard', () async {
      final root = await _project({
        'lib/pages/index.page.dart':
            "import 'package:dartvel_core/dartvel.dart';\n"
            '@DVPage()\nWidget _index() => const Placeholder();\n',
        'lib/pages/_layout.dart': 'class RootLayout {}\n',
        'lib/pages/blog/_layout.dart': 'class BlogLayout {}\n',
        'lib/pages/blog/_guard.dart': 'class BlogGuard {}\n',
      });
      try {
        final layouts = discoverLayouts(root: root.path, pagesDir: 'lib/pages');
        final guards = discoverGuards(root: root.path, pagesDir: 'lib/pages');

        // Two layouts and one guard exist; finding fewer means the pattern
        // matched nothing, which is the failure this test exists for.
        expect(layouts, hasLength(2), reason: 'root and blog layouts');
        expect(guards, hasLength(1), reason: 'the blog guard');
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('a project with no layouts finds none, without failing', () async {
      final root = await _project({
        'lib/pages/index.page.dart': 'const x = 1;\n',
      });
      try {
        expect(discoverLayouts(root: root.path, pagesDir: 'lib/pages'),
            isEmpty);
      } finally {
        root.deleteSync(recursive: true);
      }
    });
  });
}

// Appended: the root guard case, which had no handling at all. `**/` requires
// at least one directory, so a `_guard.dart` sitting directly in pagesDir was
// never matched — and a guard for the whole application is the most likely one
// anybody writes.
void rootGuardTests() {
  group('a guard at the root of pagesDir', () {
    test('is discovered, the way a root layout already was', () async {
      final root = await _project({
        'lib/pages/index.page.dart': 'const x = 1;\n',
        'lib/pages/_guard.dart': 'class AppGuard {}\n',
      });
      try {
        expect(
          discoverGuards(root: root.path, pagesDir: 'lib/pages')
              .map((f) => f.path.split('/').last),
          <String>['_guard.dart'],
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    });


    test('a file is discovered once, however the glob behaves', () async {
      // The root file is added by name and `**/` is supposed not to match it.
      // That held locally and did not hold on CI, where the same _guard.dart
      // came back twice -- a duplicated guard runs twice, and a duplicated
      // layout wraps the page twice. The invariant is the file, not the glob.
      final root = await _project({
        'lib/pages/index.page.dart': 'const x = 1;\n',
        'lib/pages/_guard.dart': 'class AppGuard {}\n',
        'lib/pages/_layout.dart': 'class AppLayout {}\n',
        'lib/pages/blog/_guard.dart': 'class BlogGuard {}\n',
      });
      try {
        for (final List<File> found in <List<File>>[
          discoverGuards(root: root.path, pagesDir: 'lib/pages'),
          discoverLayouts(root: root.path, pagesDir: 'lib/pages'),
        ]) {
          final List<String> paths =
              found.map((File f) => f.absolute.path).toList();
          expect(paths.toSet(), hasLength(paths.length),
              reason: 'no path may appear twice');
        }
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('a root layout is still discovered alongside nested ones', () async {
      final root = await _project({
        'lib/pages/_layout.dart': 'class RootLayout {}\n',
        'lib/pages/blog/_layout.dart': 'class BlogLayout {}\n',
      });
      try {
        expect(
          discoverLayouts(root: root.path, pagesDir: 'lib/pages'),
          hasLength(2),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    });
  });
}
