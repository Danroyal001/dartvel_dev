// A spilled object is deleted when the value that spilled it goes away.
//
// A value over the spill threshold is written to file storage and a pointer
// to it goes into the preference store. Removing the key cleared the pointer
// and left the object behind, and shrinking the value below the threshold
// wrote the new value inline and left the old object behind too -- so the
// bytes stayed on disk, or in a bucket, for the life of the installation with
// nothing referring to them.
//
// `sweepAfter` is the setting the specification names for this and it cannot
// be honoured: DVFileStorageAdapter has list and delete and no notion of when
// an object was written, so "older than 24h" is not a question this interface
// can answer. Deleting on removal needs no age, and is the half that is
// actually correct rather than a tidy-up after the fact.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'window_shared_store_helpers.dart';

/// Longer than the 64-byte threshold the store is built with below.
DVJsonString big() => DVJsonString('x' * 200);

void main() {
  late NotifyingBackend backend;
  late DVMemoryFileStorageAdapter files;
  late DVWindowSharedStore store;

  setUp(() {
    backend = NotifyingBackend();
    files = DVMemoryFileStorageAdapter();
    store = DVWindowSharedStore(
      backend: backend,
      spillStorage: files,
      spillThresholdBytes: 64,
      debounce: Duration.zero,
    );
  });
  tearDown(() => store.dispose());

  test('a big value spills, so there is something to leak', () async {
    await store.set('draft', big());
    expect(await files.list(prefix: 'dartvel/window-shared/'), isNotEmpty);
  });

  test('removing the key deletes the object it pointed at', () async {
    await store.set('draft', big());
    await store.remove('draft');

    expect(await files.list(prefix: 'dartvel/window-shared/'), isEmpty);
    expect(backend.values.containsKey('draft'), isFalse);
  });

  test('a value that shrinks below the threshold takes its object with it',
      () async {
    await store.set('draft', big());
    await store.set('draft', const DVJsonString('short'));

    expect(await files.list(prefix: 'dartvel/window-shared/'), isEmpty);
    expect(backend.values['draft'], contains('short'));
  });

  // The name is derived from the key, so a rewrite that still spills replaces
  // the object rather than adding one. Asserted because the cleanup must not
  // delete the object it has just written.
  test('a big value rewritten big keeps exactly one object', () async {
    await store.set('draft', big());
    await store.set('draft', DVJsonString('y' * 300));

    expect(await files.list(prefix: 'dartvel/window-shared/'), hasLength(1));
    expect(await store.get('draft'), isNotNull);
  });

  test('removing a key that never spilled is not an error', () async {
    await store.set('small', const DVJsonString('a'));
    await store.remove('small');
    expect(await files.list(prefix: 'dartvel/window-shared/'), isEmpty);
  });
}
