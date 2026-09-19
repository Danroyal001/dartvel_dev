// What the page editor's toolbar offers, in the words a site owner uses.
//
// Studio runs on the server, and it is used by people who never open a
// terminal as well as by the developers who do. The button that makes a page
// live says Deploy, the word `dartvel deploy` uses, and its menu holds the
// other ways out: deploy now, or put the page from the last build back.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host() => const MaterialApp(home: Material(child: DVStudioScreen()));

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

  // Opening and closing the windows of whichever app happened to host Studio
  // was never something a site owner needed.
  testWidgets('there is no Windows section', (WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Windows'), findsNothing);
    expect(find.text('Open windows'), findsNothing);
  });

  testWidgets('Deploy now from the menu deploys the page',
      (WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, '/menu');
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-create')));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey<String>('dv-studio-deploy-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deploy now'));
    await tester.pumpAndSettle();

    expect(await const DVPageStore().routes(), <String>['/menu']);
  });

  // The button says Deploy, so the overview that explains it must not send
  // the owner looking for a Publish button that is not there.
  testWidgets('the overview speaks of deploying', (WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.textContaining(RegExp('publish', caseSensitive: false)),
        findsNothing);
  });
}
