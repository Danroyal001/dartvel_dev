// DVPreferenceStore: small values kept for one visitor between visits, read
// synchronously so a setting is in force before the first frame.
// localStorage in a browser, a file per key on a device, memory elsewhere.
@TestOn('vm')
library;

import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(DVPreferenceStore.reset);

  test('the memory store reads back what was written, and forgets a removed key', () {
    final DVMemoryPreferenceStore store = DVMemoryPreferenceStore();
    expect(store.read('app.voice'), isNull);
    store.write('app.voice', '{"position":"centre"}');
    expect(store.read('app.voice'), '{"position":"centre"}');
    store.remove('app.voice');
    expect(store.read('app.voice'), isNull);
  });

  test('a test can replace the store every caller uses', () {
    final DVMemoryPreferenceStore store = DVMemoryPreferenceStore();
    DVPreferenceStore.instance = store;
    DVPreferenceStore.instance.write('k', 'v');
    expect(store.read('k'), 'v');
    DVPreferenceStore.reset();
    expect(identical(DVPreferenceStore.instance, store), isFalse);
  });

  test('the file store keeps one file per key and survives a new instance', () {
    final Directory directory = Directory.systemTemp.createTempSync('dv-preferences');
    addTearDown(() => directory.deleteSync(recursive: true));
    DVFilePreferenceStore(directory.path).write('dartvel.accessibility', '{"highContrast":true}');
    expect(DVFilePreferenceStore(directory.path).read('dartvel.accessibility'), '{"highContrast":true}');
    expect(directory.listSync().whereType<File>().map((File f) => f.uri.pathSegments.last), <String>['dartvel.accessibility.json']);
    DVFilePreferenceStore(directory.path).remove('dartvel.accessibility');
    expect(DVFilePreferenceStore(directory.path).read('dartvel.accessibility'), isNull);
  });

  test('a key that is not a plain name is refused rather than written outside the directory', () {
    final Directory directory = Directory.systemTemp.createTempSync('dv-preferences');
    addTearDown(() => directory.deleteSync(recursive: true));
    expect(() => DVFilePreferenceStore(directory.path).write('../escape', 'x'), throwsArgumentError);
  });

  test('an unwritable directory is not a reason to stop the app', () {
    final DVFilePreferenceStore store = DVFilePreferenceStore('/proc/no-such-place');
    store.write('k', 'v');
    expect(store.read('k'), isNull);
  });
}
