// Page bundles: how an editor change reaches an app that is installed rather
// than merely running. The bundle travels with a release or OTA patch and is
// applied into the store, from which the override machinery takes over.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument documentFor(String route, String text) {
  final document = DVPageDocument(route: route, title: text);
  DVPageDocumentEditor(document)
      .insert(DVPageNode.text(text), parent: document.root.id);
  return document;
}

void main() {
  late SqliteDVDatabaseAdapter database;
  const installer = DVPageBundleInstaller();

  setUp(() {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
  });

  tearDown(() {
    database.close();
    DVPageStore.resetCache();
  });

  test('a bundle round-trips through its wire format', () {
    final bundle = DVPageBundle(
      version: '1.4.0',
      pages: <DVPageDocument>[documentFor('/promo', 'Sale')],
      removedRoutes: const <String>['/old'],
    );

    final restored = DVPageBundle.decode(bundle.encode());

    expect(restored.version, '1.4.0');
    expect(restored.pages.single.route, '/promo');
    expect(restored.removedRoutes, <String>['/old']);
  });

  test('a bundle without a version is rejected', () {
    // Version is what makes a bundle identifiable and rollback-able; a
    // versionless one could be applied repeatedly with no record.
    expect(
      () => DVPageBundle.decode('{"pages": []}'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('applying writes the documents into the store', () async {
    final applied = await installer.apply(
      DVPageBundle(
        version: '1.0.0',
        pages: <DVPageDocument>[
          documentFor('/promo', 'Shipped'),
          documentFor('/terms', 'Terms'),
        ],
      ),
    );

    expect(applied, isTrue);
    expect(await const DVPageStore().routes(), <String>['/promo', '/terms']);
    expect((await const DVPageStore().load('/promo'))!.title, 'Shipped');
    expect(await installer.appliedVersions(), <String>['1.0.0']);
  });

  test('applying the same version twice is a no-op', () async {
    // An OTA patch can be delivered more than once; re-applying would undo
    // edits made since it landed.
    await installer.apply(
      DVPageBundle(
        version: '1.0.0',
        pages: <DVPageDocument>[documentFor('/promo', 'Shipped')],
      ),
    );
    await const DVPageStore().save(documentFor('/promo', 'Edited After'));

    final reapplied = await installer.apply(
      DVPageBundle(
        version: '1.0.0',
        pages: <DVPageDocument>[documentFor('/promo', 'Shipped')],
      ),
    );

    expect(reapplied, isFalse);
    expect((await const DVPageStore().load('/promo'))!.title, 'Edited After');
  });

  test('a later version applies over an earlier one', () async {
    await installer.apply(
      DVPageBundle(
        version: '1.0.0',
        pages: <DVPageDocument>[documentFor('/promo', 'v1')],
      ),
    );
    await installer.apply(
      DVPageBundle(
        version: '1.1.0',
        pages: <DVPageDocument>[documentFor('/promo', 'v2')],
      ),
    );

    expect((await const DVPageStore().load('/promo'))!.title, 'v2');
    expect(await installer.appliedVersions(), <String>['1.0.0', '1.1.0']);
  });

  test('removedRoutes withdraws an edit, restoring the compiled page',
      () async {
    await installer.apply(
      DVPageBundle(
        version: '1.0.0',
        pages: <DVPageDocument>[documentFor('/about', 'Edited')],
      ),
    );
    expect(await const DVPageStore().load('/about'), isNotNull);

    await installer.apply(
      const DVPageBundle(version: '1.1.0', removedRoutes: <String>['/about']),
    );

    // Nothing overrides /about any more, so the compiled page serves again.
    expect(await const DVPageStore().load('/about'), isNull);
  });

  test('forget lets a version be applied again', () async {
    final bundle = DVPageBundle(
      version: '1.0.0',
      pages: <DVPageDocument>[documentFor('/promo', 'Shipped')],
    );
    await installer.apply(bundle);
    await installer.forget('1.0.0');

    expect(await installer.apply(bundle), isTrue);
  });

  testWidgets('an applied bundle reaches a page already on screen',
      (WidgetTester tester) async {
    // The whole point: an OTA patch lands and the running app updates,
    // without navigation, through the same change stream an editor save uses.
    await tester.pumpWidget(
      const MaterialApp(
        home: DVStudioPageRoute('/promo', fallback: Text('compiled page')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('compiled page'), findsOneWidget);

    await installer.apply(
      DVPageBundle(
        version: '2.0.0',
        pages: <DVPageDocument>[documentFor('/promo', 'from the patch')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('from the patch'), findsOneWidget);
    expect(find.text('compiled page'), findsNothing);
  });
}
