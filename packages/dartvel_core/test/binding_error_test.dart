// A foreign error crossing a binding becomes a typed Dart exception that
// carries the module id, the operation, the binding kind and the original
// error. An error that loses its origin at the boundary is one a developer
// debugs twice. Dartvel's own module exceptions already carry their origin
// and pass through unchanged.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

void main() {
  test('a synchronous foreign throw becomes a DVBindingError', () {
    final StateError original = StateError('zlib: stream error');
    expect(
      () => dvBindingCall<int>('zlib', 'crc32', 'DVFfiBinding',
          () => throw original),
      throwsA(isA<DVBindingError>()
          .having((DVBindingError e) => e.module, 'module', 'zlib')
          .having((DVBindingError e) => e.operation, 'operation', 'crc32')
          .having((DVBindingError e) => e.binding, 'binding', 'DVFfiBinding')
          .having((DVBindingError e) => e.error, 'error', same(original))
          .having((DVBindingError e) => e.toString(), 'message',
              allOf(contains('zlib.crc32'), contains('DVFfiBinding'),
                  contains('stream error')))),
    );
  });

  test('a value passes through untouched', () {
    expect(dvBindingCall<int>('zlib', 'crc32', 'DVFfiBinding', () => 7), 7);
  });

  test('a failed Future becomes a DVBindingError, keeping its stack trace',
      () async {
    final StackTrace origin = StackTrace.current;
    final Future<String> call = dvBindingFuture<String>(
        'slug', 'slugify', 'DVNodeJsBinding',
        () => Future<String>.error('node exited 1', origin));
    await expectLater(
        call,
        throwsA(isA<DVBindingError>()
            .having((DVBindingError e) => e.error, 'error', 'node exited 1')
            .having((DVBindingError e) => e.stackTrace, 'stackTrace',
                same(origin))));
  });

  test('a throw before the Future exists is converted too', () async {
    await expectLater(
        dvBindingFuture<String>('slug', 'slugify', 'DVNodeJsBinding',
            () => throw ArgumentError('bad')),
        throwsA(isA<DVBindingError>()));
  });

  test('a Stream error becomes a DVBindingError and the values still arrive',
      () async {
    final StreamController<int> source = StreamController<int>();
    final List<int> values = <int>[];
    final List<Object> errors = <Object>[];
    final Completer<void> done = Completer<void>();
    dvBindingStream<int>(
            'scanner', 'scans', 'DVJniBinding', () => source.stream)
        .listen(values.add, onError: (Object e) => errors.add(e),
            onDone: done.complete);
    source
      ..add(1)
      ..addError(Exception('camera gone'))
      ..add(2);
    await source.close();
    await done.future;
    expect(values, <int>[1, 2]);
    expect(errors.single, isA<DVBindingError>()
        .having((DVBindingError e) => e.operation, 'operation', 'scans')
        .having((DVBindingError e) => '${e.error}', 'error',
            contains('camera gone')));
  });

  test('Dartvel module exceptions pass through unchanged', () {
    expect(
      () => dvBindingCall<int>('scanner', 'scan', 'DVJniBinding',
          () => throw const DVModuleUnavailable(
              'scanner', 'scan', DVModuleEnvironment.web)),
      throwsA(isA<DVModuleUnavailable>()),
    );
  });
}
