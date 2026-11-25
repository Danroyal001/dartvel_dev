// Owner, 19 Nov 2026, on dartvel.dev/studio at a laptop width: "WTF is all
// these gap to the right?". A band of text kept its paragraphs at reading
// width inside the 1040-pixel column, so the right half of the page was
// empty. On a wide screen a text band now reads as two columns -- its label
// and heading on the left, its paragraphs on the right, still at reading
// width -- and fills the column. On a phone it stays one column.
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:dartvel_site/pages/_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget routed(Widget page) => MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/studio',
        routes: <RouteBase>[
          for (final String path in const <String>['/', '/docs', '/features', '/studio', '/cloud'])
            GoRoute(
              path: path,
              builder: (BuildContext context, GoRouterState state) => Scaffold(body: Layout(child: page)),
            ),
        ],
      ),
    );

const String heading = 'Controls support keyboard and screen reader input.';
const String paragraph = 'Tab reaches every button';
const String firstParagraph = 'On sign-in, the email and password fields';

Future<(Rect, Rect)> measure(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(routed(const StudioPageGeneratedPage()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(seconds: 2));
  final Rect title = tester.getRect(find.textContaining(heading, findRichText: true).first);
  final Rect body = tester.getRect(find.textContaining(paragraph, findRichText: true).first);
  return (title, body);
}

void main() {
  setUpAll(() async {
    await StudioPageGeneratedPage.loadLibrary();
  });
  setUp(dvResetDeferredPages);

  testWidgets('on a laptop a text band fills its column in two columns', (WidgetTester tester) async {
    final (Rect title, Rect body) = await measure(tester, const Size(1366, 900));
    expect(body.left, greaterThan(title.right - 1), reason: 'the paragraphs sit beside the heading, not under it');
    final Rect first = tester.getRect(find.textContaining(firstParagraph, findRichText: true).first);
    expect(first.top, lessThan(title.bottom), reason: 'the first paragraph starts beside the heading');
    // The column is 1040 wide from the heading's left edge.
    expect(body.right, greaterThan(title.left + 1040 - 48), reason: 'no empty half of the page on the right');
    expect(body.width, lessThanOrEqualTo(680), reason: 'still a readable line length');
    expect(tester.takeException(), isNull);
  });

  pictureBandTests();
  codeBandTests();

  testWidgets('on a phone it stays one column', (WidgetTester tester) async {
    final (Rect title, Rect body) = await measure(tester, const Size(390, 844));
    expect(body.left, moreOrLessEquals(title.left, epsilon: 0.5));
    expect(body.top, greaterThan(title.bottom - 1));
    expect(tester.takeException(), isNull);
  });
}

// Owner's screenshot again (20 Nov check on the spare): the bands that also
// carry a picture of Studio -- Page builder, Data -- kept their paragraphs in
// the left half above the picture, with the right half of the column empty.
// Their text reads in two columns too, and the picture stays full width below.
const String pictureBandHeading = 'Drag a page together, then keep it as an ordinary @DVPage.';
const String pictureBandParagraph = 'Insert text, images, buttons, spacers and dividers';

void pictureBandTests() {
  testWidgets('on a laptop a band with a picture lays its text out in two columns too', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(routed(const StudioPageGeneratedPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 2));
    final Rect title = tester.getRect(find.textContaining(pictureBandHeading, findRichText: true).first);
    final Rect body = tester.getRect(find.textContaining(pictureBandParagraph, findRichText: true).first);
    expect(body.left, greaterThan(title.right - 1), reason: 'the paragraphs sit beside the heading, not under it');
    expect(body.top, lessThan(title.bottom), reason: 'the first paragraph starts beside the heading');
    expect(body.right, greaterThan(title.left + 1040 - 48), reason: 'no empty half of the column on the right');
    expect(tester.takeException(), isNull);
  });
}

// The Free Studio band opens with a code sample before its paragraphs; it is
// text too, so it goes to the right column with them.
void codeBandTests() {
  testWidgets('on a laptop a band whose text includes a code sample reads in two columns', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(routed(const StudioPageGeneratedPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 2));
    final Rect title = tester.getRect(find.textContaining('Open Studio on your live server with one grant.', findRichText: true).first);
    final Rect code = tester.getRect(find.textContaining('# pubspec.yaml', findRichText: true).first);
    final Rect body = tester.getRect(find.textContaining('Only people you grant can open it.', findRichText: true).first);
    expect(code.left, greaterThan(title.right - 1), reason: 'the code sample sits beside the heading');
    expect(code.top, lessThan(title.bottom), reason: 'it starts beside the heading, not under it');
    expect(body.left, greaterThan(title.right - 1), reason: 'the paragraphs follow the code in the right column');
    expect(tester.takeException(), isNull);
  });
}
