// Publishing as a seam: the controller's save goes through its publisher,
// which by default is the page store. Whatever attaches to the editor can
// replace it -- an approval step that holds the page for review is the case
// -- and the Pages tab's Publish button does not need to know.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SqliteDVDatabaseAdapter database;

  setUp(() {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
  });

  tearDown(() {
    database.close();
    DVPageStore.resetCache();
  });

  test('by default, save publishes to the page store', () async {
    final DVStudioEditorController c =
        DVStudioEditorController(DVPageDocument(route: '/p', title: 'one'));
    await c.save();
    DVPageStore.resetCache();
    expect((await const DVPageStore().load('/p'))!.title, 'one');
  });

  test('with a publisher set, save goes there and nowhere else', () async {
    final DVStudioEditorController c =
        DVStudioEditorController(DVPageDocument(route: '/p', title: 'one'));
    final List<String> held = <String>[];
    c.publisher = (DVPageDocument document) async => held.add(document.title);

    await c.save();

    expect(held, <String>['one']);
    expect(await const DVPageStore().load('/p'), isNull,
        reason: 'the page store is not written behind the publisher\'s back');
  });

  test('clearing the publisher restores the default', () async {
    final DVStudioEditorController c =
        DVStudioEditorController(DVPageDocument(route: '/p', title: 'one'));
    c.publisher = (DVPageDocument _) async {};
    c.publisher = null;
    await c.save();
    DVPageStore.resetCache();
    expect((await const DVPageStore().load('/p'))!.title, 'one');
  });
}
