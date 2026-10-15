// A page built in Studio says what it is about to the browser it is drawn
// in, not only to a crawler: moving to it in the app sets its title,
// description and indexing rule as a page of the application's own does.
import 'package:dartvel_core/dartvel.dart' show SqliteDVDatabaseAdapter;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SqliteDVDatabaseAdapter database;

  setUp(() {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
    addTearDown(() {
      database.close();
      DVPageStore.resetCache();
    });
  });

  testWidgets('a Studio page carries its own SEO', (WidgetTester tester) async {
    await const DVPageStore().save(DVPageDocument(
      route: '/sale',
      title: 'Autumn sale',
      description: 'Our autumn sale.',
      image: '/_dartvel/media/sale.png',
      robots: 'noindex',
      canonicalUrl: 'https://harbour.example/sale',
      schemaType: 'Product',
    ));
    await tester.pumpWidget(const MaterialApp(home: DVStudioPageRoute('/sale')));
    await tester.pumpAndSettle();

    final DartvelSeo seo = tester.widget<DartvelSeo>(find.byType(DartvelSeo));
    expect(seo.props.title, 'Autumn sale');
    expect(seo.props.description, 'Our autumn sale.');
    expect(seo.props.imageUrl, '/_dartvel/media/sale.png');
    expect(seo.props.canonicalUrl, 'https://harbour.example/sale');
    expect(seo.props.extraMeta['robots'], 'noindex');
    expect(seo.props.structuredData?['@type'], 'Product');
  });
}
