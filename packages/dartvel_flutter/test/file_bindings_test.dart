// The files.* bindings.
//
// Reading and writing bytes is the easy part. The part worth testing is the
// confinement: a binding that writes wherever it is told is a file-write
// primitive handed to whatever can reach it, and every way of escaping a root
// directory looks like an ordinary path until it lands somewhere else.
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_flutter/src/platform/file_bindings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Map<String, Object? Function(Object?)> handlers;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dv_files_');
    handlers = <String, Object? Function(Object?)>{};
    DVFileBindings.reset();
    DVFileBindings.register(
      root.path,
      (String name, Object? Function(Object?) handler) =>
          handlers[name] = handler,
    );
  });

  tearDown(() {
    DVFileBindings.reset();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Object? call(String name, Map<String, Object?> arguments) =>
      handlers[name]!(arguments);

  test('all three bindings register', () {
    expect(
      handlers.keys,
      containsAll(<String>['files.readBytes', 'files.writeBytes', 'files.delete']),
    );
  });

  test('bytes written come back unchanged', () {
    final Uint8List bytes =
        Uint8List.fromList(List<int>.generate(512, (int i) => i % 256));

    expect(call('files.writeBytes', <String, Object?>{
      'path': 'blob.bin',
      'bytes': bytes,
    }), 512);
    expect(call('files.readBytes', <String, Object?>{'path': 'blob.bin'}), bytes);
  });

  test('a nested path creates its directories', () {
    call('files.writeBytes', <String, Object?>{
      'path': 'a/b/c/note.txt',
      'bytes': <int>[1, 2, 3],
    });

    expect(File(p.join(root.path, 'a/b/c/note.txt')).existsSync(), isTrue);
  });

  test('delete removes the file and says so', () {
    call('files.writeBytes',
        <String, Object?>{'path': 'gone.txt', 'bytes': <int>[1]});

    expect(call('files.delete', <String, Object?>{'path': 'gone.txt'}), isTrue);
    expect(File(p.join(root.path, 'gone.txt')).existsSync(), isFalse);
  });

  test('deleting what is absent is false, not an exception', () {
    // The caller's intent either way; throwing would make every call site
    // wrap it.
    expect(call('files.delete', <String, Object?>{'path': 'never.txt'}), isFalse);
  });

  test('reading what is absent is an error, not empty bytes', () {
    // Empty bytes are a valid file. Returning them for a missing one makes
    // "not there" and "there and empty" the same answer.
    expect(
      () => call('files.readBytes', <String, Object?>{'path': 'never.txt'}),
      throwsArgumentError,
    );
  });

  group('confinement', () {
    test('a relative path escaping the root is refused', () {
      // Note the prefix check that would pass this: the string starts inside
      // the root and resolves outside it.
      expect(
        () => call('files.readBytes',
            <String, Object?>{'path': 'a/../../../etc/passwd'}),
        throwsArgumentError,
      );
    });

    test('a bare parent traversal is refused', () {
      expect(
        () => call('files.readBytes', <String, Object?>{'path': '../secret'}),
        throwsArgumentError,
      );
    });

    test('an absolute path outside the root is refused', () {
      expect(
        () => call('files.readBytes', <String, Object?>{'path': '/etc/passwd'}),
        throwsArgumentError,
      );
    });

    test('a sibling directory sharing the root prefix is refused', () {
      // `/tmp/dv_files_x-other` starts with `/tmp/dv_files_x` as a string and
      // is a different directory. A prefix check accepts it.
      final Directory sibling = Directory('${root.path}-other')
        ..createSync(recursive: true);
      addTearDown(() => sibling.deleteSync(recursive: true));
      File(p.join(sibling.path, 'secret.txt')).writeAsStringSync('secret');

      expect(
        () => call('files.readBytes',
            <String, Object?>{'path': p.join(sibling.path, 'secret.txt')}),
        throwsArgumentError,
      );
    });

    test('a symlink pointing out of the root is refused', () {
      // The check is on the resolved path, not the one supplied. A symlink is
      // an ordinary-looking name that lands anywhere.
      final File outside = File(p.join(root.parent.path, 'outside.txt'))
        ..writeAsStringSync('secret');
      addTearDown(() => outside.deleteSync());
      Link(p.join(root.path, 'link.txt')).createSync(outside.path);

      expect(
        () => call('files.readBytes', <String, Object?>{'path': 'link.txt'}),
        throwsArgumentError,
      );
    });

    test('a write cannot escape either', () {
      expect(
        () => call('files.writeBytes', <String, Object?>{
          'path': '../escaped.txt',
          'bytes': <int>[1],
        }),
        throwsArgumentError,
      );
    });

    test('the root itself is reachable', () {
      // Confinement must not exclude the directory it confines to, or a path
      // of '.' fails for no reason a caller can see.
      expect(
        () => call('files.readBytes', <String, Object?>{'path': 'ok.txt'}),
        throwsArgumentError,
      );
      call('files.writeBytes',
          <String, Object?>{'path': 'ok.txt', 'bytes': <int>[1]});
      expect(call('files.readBytes', <String, Object?>{'path': 'ok.txt'}),
          <int>[1]);
    });
  });

  group('arguments', () {
    test('a missing path is refused', () {
      expect(() => call('files.readBytes', <String, Object?>{}),
          throwsArgumentError);
    });

    test('an empty path is refused', () {
      expect(() => call('files.readBytes', <String, Object?>{'path': ''}),
          throwsArgumentError);
    });

    test('bytes that are not bytes are refused, not stringified', () {
      // Writing the string form of a value produces a file that looks written
      // and contains the wrong thing.
      expect(
        () => call('files.writeBytes',
            <String, Object?>{'path': 'x.bin', 'bytes': 'not bytes'}),
        throwsArgumentError,
      );
      expect(File(p.join(root.path, 'x.bin')).existsSync(), isFalse);
    });
  });
}
