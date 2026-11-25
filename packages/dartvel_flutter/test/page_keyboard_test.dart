// A page that does not shrink for the on-screen keyboard
// (resizeToAvoidBottomInset: false) keeps its box while the keyboard comes and
// goes, and reads the keyboard as an inset over that box (owner, 25 Nov 2026,
// on the Dev Launcher on his phone: "launching the on-screen keyboard ruins
// everything").
//
// Android reports the keyboard as a bottom view inset measured from the
// bottom of the screen, and while the keyboard covers the navigation bar it
// reports the bar's padding as nothing. The shell's SafeArea took the padding,
// so the moment the keyboard came up the page grew under the navigation bar:
// everything on its bottom edge (a dock, a bottom bar) moved down by the bar's
// height. And the page read the keyboard from the bottom of the screen, not
// from its own bottom edge, so a list ended above the keyboard by the bar's
// height. Here the page keeps the room above the navigation bar
// (SafeArea.maintainBottomViewPadding) and its insets are measured from its
// own box: viewInsets.bottom is how far the keyboard reaches up the page, and
// no navigation bar is left under it.
//
// A page that resizes (the default) is unchanged: it ends at the keyboard.
import 'package:dartvel_core/dartvel.dart' show DVPageShellMode;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/widgets/page_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const double statusBar = 24;
const double navigationBar = 48;
const double keyboard = 300;
const Size screenSize = Size(400, 800);

void phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = screenSize;
  tester.view.padding = const FakeViewPadding(top: statusBar, bottom: navigationBar);
  tester.view.viewPadding = const FakeViewPadding(top: statusBar, bottom: navigationBar);
  addTearDown(tester.view.reset);
}

/// The keyboard [shown] points tall, as Android reports it.
void keyboardAt(WidgetTester tester, double shown) {
  tester.view.viewInsets = FakeViewPadding(bottom: shown);
  tester.view.padding = FakeViewPadding(top: statusBar, bottom: (navigationBar - shown).clamp(0.0, navigationBar));
}

/// A page the way an app with a search field and a bottom bar writes it: a
/// list over the room the keyboard leaves, and a bar on the bottom edge.
class SearchPage extends StatelessWidget {
  const SearchPage({super.key, required this.seen});

  final List<MediaQueryData> seen;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    seen.add(media);
    return Stack(
      children: <Widget>[
        Column(
          children: <Widget>[
            const TextField(key: Key('search')),
            Expanded(
              child: ListView(
                key: const Key('results'),
                children: <Widget>[for (int row = 0; row < 40; row++) SizedBox(height: 50, child: Text('Row $row'))],
              ),
            ),
            SizedBox(height: media.viewInsets.bottom),
          ],
        ),
        const Align(alignment: Alignment.bottomCenter, child: SizedBox(key: Key('bottom bar'), height: 56, width: 400)),
      ],
    );
  }
}

Widget app(Widget page, {required bool resize, DVPageShellMode shell = DVPageShellMode.material}) => MaterialApp(
      home: DVPageShell(
        spec: DVPageScaffoldSpec(title: 'Search', shell: shell, resizeToAvoidBottomInset: resize),
        child: page,
      ),
    );

void main() {
  setUp(DVPageScrollMemory.reset);
  tearDown(DVPageScrollMemory.reset);

  for (final DVPageShellMode shell in <DVPageShellMode>[DVPageShellMode.material, DVPageShellMode.cupertino]) {
    group('${shell.name} shell, a page that does not resize for the keyboard', () {
      testWidgets('keeps its box on every frame of the keyboard, and reads the keyboard from its own bottom edge', (WidgetTester tester) async {
        phone(tester);
        final List<MediaQueryData> seen = <MediaQueryData>[];
        await tester.pumpWidget(app(SearchPage(seen: seen), resize: false, shell: shell));
        await tester.pumpAndSettle();
        final Rect barBefore = tester.getRect(find.byKey(const Key('bottom bar')));
        final Size pageBefore = seen.last.size;
        expect(barBefore.bottom, screenSize.height - navigationBar, reason: 'the bar sits on the navigation bar');
        expect(seen.last.viewInsets.bottom, 0);

        for (int frame = 1; frame <= 12; frame++) {
          final double shown = keyboard * frame / 12;
          keyboardAt(tester, shown);
          await tester.pump(const Duration(milliseconds: 20));
          expect(tester.takeException(), isNull);
          expect(tester.getRect(find.byKey(const Key('bottom bar'))), barBefore, reason: 'frame $frame: the bottom bar does not move');
          expect(seen.last.size, pageBefore, reason: 'frame $frame: the page keeps its size');
          final double over = (shown - navigationBar).clamp(0.0, keyboard);
          expect(seen.last.viewInsets.bottom, moreOrLessEquals(over), reason: 'frame $frame: the keyboard reaches $over up the page');
          expect(seen.last.viewPadding.bottom, 0, reason: 'frame $frame: no navigation bar left under the page');
          expect(tester.getRect(find.byKey(const Key('results'))).bottom, lessThanOrEqualTo(screenSize.height - shown + 0.01), reason: 'frame $frame: the list ends at the keyboard');
        }
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byKey(const Key('results'))).bottom, moreOrLessEquals(screenSize.height - keyboard), reason: 'the list uses the room down to the keyboard');

        keyboardAt(tester, 0);
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byKey(const Key('bottom bar'))), barBefore);
        expect(seen.last.size, pageBefore);
        expect(seen.last.viewInsets.bottom, 0);
        expect(tester.getRect(find.byKey(const Key('results'))).bottom, screenSize.height - navigationBar);
      });
    });

    testWidgets('${shell.name} shell, a page that resizes (the default) still ends at the keyboard', (WidgetTester tester) async {
      phone(tester);
      final List<MediaQueryData> seen = <MediaQueryData>[];
      await tester.pumpWidget(app(SearchPage(seen: seen), resize: true, shell: shell));
      await tester.pumpAndSettle();
      keyboardAt(tester, keyboard);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byKey(const Key('bottom bar'))).bottom, screenSize.height - keyboard, reason: 'the page ends at the keyboard');
      expect(seen.last.viewInsets.bottom, 0, reason: 'nothing of the page is under the keyboard');
      expect(tester.getRect(find.byKey(const Key('results'))).bottom, moreOrLessEquals(screenSize.height - keyboard));
    });
  }
}
