import 'dart:io';

import 'package:rust_stack_phase0/line_count.dart';
import 'package:test/test.dart';

void main() {
  group('countNonBlank', () {
    test('counts lines with any non-whitespace character', () {
      expect(countNonBlank('a\n\n  \n\tb\nc'), 3);
    });

    test('a comment line counts, because it is a line someone ports', () {
      expect(countNonBlank('// header\nint x = 1;\n'), 2);
    });

    test('empty text and a trailing newline add nothing', () {
      expect(countNonBlank(''), 0);
      expect(countNonBlank('x\n'), 1);
    });

    test('Windows line endings do not double the count', () {
      expect(countNonBlank('a\r\n\r\nb\r\n'), 2);
    });
  });

  group('languageOf', () {
    test(
      'Dart',
      () => expect(languageOf('pkg/analyzer/lib/a.dart'), Language.dart),
    );

    test('C and C++ sources and headers are one language', () {
      for (final path in ['vm/a.cc', 'a.cpp', 'a.cxx', 'a.h', 'a.hpp', 'a.c']) {
        expect(languageOf(path), Language.cpp, reason: path);
      }
    });

    test('Objective-C and Objective-C++', () {
      expect(languageOf('shell/platform/darwin/a.mm'), Language.objc);
      expect(languageOf('shell/platform/darwin/a.m'), Language.objc);
    });

    test('anything else is not counted', () {
      for (final path in ['a.java', 'a.py', 'BUILD.gn', 'a.md', 'Makefile']) {
        expect(languageOf(path), isNull, reason: path);
      }
    });
  });

  group('isTestPath', () {
    test('a directory named for tests marks everything under it', () {
      for (final path in [
        'pkg/analyzer/test/src/a.dart',
        'pkg/front_end/testcases/general/a.dart',
        'runtime/tests/vm/a.dart',
        'pkg/linter/test_data/rules/a.dart',
        'pkg/compiler/testing/a.dart',
        'pkg/analyzer/benchmark/a.dart',
        'impeller/fixtures/a.cc',
        'pkg/front_end/test/fasta/fixtures/a.dart',
      ]) {
        expect(isTestPath(path), isTrue, reason: path);
      }
    });

    test('a directory whose name ends in a test word is a test directory', () {
      // runtime/bin/ffi_test holds a 23k-line generated FFI test file; the
      // proposal counted it as a test, and a rule that only matched whole
      // names filed it under the dart:io embedder's implementation.
      for (final path in [
        'runtime/bin/ffi_test/ffi_test_functions_generated.cc',
        'runtime/bin/ffi_unit_test/run_ffi_unit_tests.cc',
        'pkg/front_end/parser_testcases/a.dart',
        'pkg/dds/dap_tests/a.dart',
      ]) {
        expect(isTestPath(path), isTrue, reason: path);
      }
    });

    test(
      'a file named for tests counts, as the VM keeps them beside the code',
      () {
        for (final path in [
          'runtime/vm/object_test.cc',
          'flow/layers/layer_tree_unittests.cc',
          'fml/memory/ref_ptr_unittest.cc',
          'pkg/dartdev/lib/a_test.dart',
          'display_list/dl_benchmarks.cc',
        ]) {
          expect(isTestPath(path), isTrue, reason: path);
        }
      },
    );

    test('implementation stays implementation', () {
      for (final path in [
        'runtime/vm/object.cc',
        'pkg/analyzer/lib/src/dart/analysis/driver.dart',
        'packages/flutter_tools/lib/src/test/flutter_platform.dart',
        'pkg/testing_helpers_are_not/lib/a.dart',
        'lib/src/contest.dart',
      ]) {
        expect(isTestPath(path), isFalse, reason: path);
      }
    });
  });

  group('measure', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('rust_stack_'));
    tearDown(() => root.deleteSync(recursive: true));

    void write(String path, String text) {
      File('${root.path}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
    }

    test('splits implementation from tests and ignores other languages', () {
      write('pkg/a/lib/a.dart', 'a\n\nb\n');
      write('pkg/a/test/a_test.dart', 'x\ny\nz\n');
      write('pkg/a/tool/run.py', 'print(1)\n');
      write('pkg/a/README.md', 'docs\n');

      final count = measure(const Component(name: 'A', roots: ['pkg/a']), root);

      expect(count.implementation, 2);
      expect(count.tests, 3);
      expect(count.byLanguage[Language.dart], 5);
      expect(count.byLanguage.containsKey(Language.cpp), isFalse);
    });

    test(
      'excluded paths are left out, so a component is not counted twice',
      () {
        write('runtime/vm/object.cc', 'a\nb\n');
        write('runtime/vm/compiler/backend.cc', 'c\nd\ne\n');

        final whole = measure(
          const Component(name: 'VM', roots: ['runtime/vm']),
          root,
        );
        final rest = measure(
          const Component(
            name: 'VM without compiler',
            roots: ['runtime/vm'],
            excludes: ['runtime/vm/compiler'],
          ),
          root,
        );

        expect(whole.implementation, 5);
        expect(rest.implementation, 2);
      },
    );

    test('a missing root is an error, not a zero', () {
      expect(
        () => measure(const Component(name: 'X', roots: ['nope']), root),
        throwsA(isA<StateError>()),
      );
    });

    test('generated and third-party directories are not counted', () {
      write('pkg/a/lib/a.dart', 'a\n');
      write('pkg/a/.dart_tool/x.dart', 'x\n');
      write('pkg/a/third_party/y.cc', 'y\n');
      write('pkg/a/build/z.dart', 'z\n');

      final count = measure(const Component(name: 'A', roots: ['pkg/a']), root);

      expect(count.implementation, 1);
    });
  });
}
