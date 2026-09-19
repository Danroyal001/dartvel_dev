// Studio's page store on a database that runs no SQL.
//
// MongoDB is the first document database Dartvel will support, and Studio is
// what a project on it opens first. The page store and the bundle installer
// wrote SQL strings; on DVMemoryRecordEngine, which refuses SQL as a document
// database does, every one of these failed naming its statement. They now
// persist through DV.Database.records.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument page(String route, String title) =>
    DVPageDocument(route: route, title: title);

void main() {
  setUp(() {
    DV.Database.configure(DVMemoryRecordEngine());
    DVPageStore.resetCache();
  });

  tearDown(() {
    DV.Database.unconfigure();
    DVPageStore.resetCache();
  });

  test('saves, loads, lists and deletes pages', () async {
    const DVPageStore store = DVPageStore();
    await store.save(page('/menu', 'Menu'));
    await store.save(page('/about', 'About'));
    await store.save(page('/menu', 'Our menu'));

    expect(await store.routes(), <String>['/about', '/menu']);
    expect((await store.load('/menu'))!.title, 'Our menu');

    await store.delete('/about');
    expect(await store.routes(), <String>['/menu']);
    expect(await store.load('/about'), isNull);
  });

  test('a fresh app reads the stored pages into its cache', () async {
    await const DVPageStore().save(page('/menu', 'Menu'));
    DVPageStore.resetCache();

    await DVPageStore.prime();

    expect(DVPageStore.cached('/menu')?.title, 'Menu');
  });

  test('a bundle applies once and records its version', () async {
    const DVPageBundleInstaller installer = DVPageBundleInstaller();
    final DVPageBundle bundle = DVPageBundle(
      version: '1.2.0',
      pages: <DVPageDocument>[page('/menu', 'Menu')],
    );

    expect(await installer.apply(bundle), isTrue);
    expect(await installer.apply(bundle), isFalse);
    expect(await installer.appliedVersions(), <String>['1.2.0']);

    await installer.forget('1.2.0');
    expect(await installer.isApplied('1.2.0'), isFalse);
  });
}
