// Display scaling: a whole app drawn to suit the screen it is on.
//
// The visual sweep of 9 Nov 2026 found every Dartvel app on a 4K signage panel
// rendered as a small column of 1x text in the middle of a black wall, and on a
// 240 px watch the header filled the face and the content was cut off. Phones,
// tablets and desktops looked right and must stay exactly as they are.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the scale for a screen', () {
    double auto(double w, double h, {DVScreenClass? declared, bool tv = false}) => dvDisplayScaleFor(
          Size(w, h),
          scaling: const DVDisplayScaling.auto(),
          declared: declared,
          television: tv,
        );

    test('phones, tablets and desktops are drawn at 1, unchanged', () {
      expect(auto(390, 844), 1);
      expect(auto(820, 1180), 1);
      expect(auto(1366, 900), 1);
      expect(auto(1920, 1080), 1, reason: 'a 1080p monitor is a desktop');
      expect(auto(2560, 1440), 1, reason: 'a 1440p monitor is a desktop');
      expect(auto(3440, 1440), 1, reason: 'an ultrawide monitor is a desktop');
      expect(auto(5760, 1080), 1, reason: 'a strip 1080 tall is sized right for its height');
    });

    test('a television is laid out as a 1280 x 720 screen, from across the room', () {
      expect(auto(1920, 1080, tv: true), 1.5);
      expect(auto(3840, 2160, tv: true), 3);
      expect(auto(960, 540, tv: true), 1, reason: 'never smaller than 1');
    });

    test('a 4K signage panel at 1x is scaled up like a television', () {
      expect(auto(3840, 2160), 3);
      expect(auto(2160, 3840), 3, reason: 'portrait signage too');
    });

    test('a declared billboard strip scales by its height', () {
      expect(auto(5760, 1080, declared: DVScreenClass.billboard), 1.5);
    });

    test('a watch is laid out as a 320 wide screen, so nothing is cut off', () {
      expect(auto(240, 240), 0.75);
      expect(auto(192, 192), 0.6);
      expect(auto(280, 800), 1, reason: 'a narrow split-screen phone is not a watch');
    });

    test('scaling can be turned off or fixed', () {
      expect(dvDisplayScaleFor(const Size(3840, 2160), scaling: const DVDisplayScaling.off()), 1);
      expect(dvDisplayScaleFor(const Size(1366, 900), scaling: const DVDisplayScaling.fixed(2)), 2);
    });
  });

  group('screen classes', () {
    test('are read from the logical size', () {
      expect(dvScreenClassFor(const Size(240, 240)), DVScreenClass.watch);
      expect(dvScreenClassFor(const Size(390, 844)), DVScreenClass.phone);
      expect(dvScreenClassFor(const Size(820, 1180)), DVScreenClass.tablet);
      expect(dvScreenClassFor(const Size(1366, 900)), DVScreenClass.desktop);
      expect(dvScreenClassFor(const Size(3840, 2160)), DVScreenClass.billboard);
      expect(dvScreenClassFor(const Size(1920, 1080), television: true), DVScreenClass.tv);
    });

    test('a television browser is recognised by its user agent', () {
      for (final String agent in const [
        'Mozilla/5.0 (SMART-TV; LINUX; Tizen 6.5) AppleWebKit/537.36 (KHTML, like Gecko) 85.0.4183.93/6.5 TV Safari/537.36',
        'Mozilla/5.0 (Web0S; Linux/SmartTV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/79.0.3945.79 Safari/537.36 WebAppManager',
        'Mozilla/5.0 (Linux; Android 9; AFTMM Build/PS7233) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0 Mobile Safari/537.36',
        'Mozilla/5.0 (Linux; Android 10; BRAVIA 4K VH2 Build/QTG3.200305.006.S292) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0 Safari/537.36',
        'Mozilla/5.0 (X11; Linux armv7l) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0 Safari/537.36 CrKey/1.56.500000',
        'Mozilla/5.0 (Linux; Android 12; Google TV Streamer) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
      ]) {
        expect(dvIsTelevisionUserAgent(agent), isTrue, reason: agent);
      }
      for (final String agent in const [
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36',
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
      ]) {
        expect(dvIsTelevisionUserAgent(agent), isFalse, reason: agent);
      }
    });
  });

  group('build settings', () {
    test('dartvel.display in pubspec arrives as defines', () {
      expect(dvDisplayScalingFromDefine(''), const DVDisplayScaling.auto());
      expect(dvDisplayScalingFromDefine('auto'), const DVDisplayScaling.auto());
      expect(dvDisplayScalingFromDefine('off'), const DVDisplayScaling.off());
      expect(dvDisplayScalingFromDefine('1.5'), const DVDisplayScaling.fixed(1.5));
      expect(dvScreenClassFromDefine('tv'), DVScreenClass.tv);
      expect(dvScreenClassFromDefine('billboard'), DVScreenClass.billboard);
      expect(dvScreenClassFromDefine(''), isNull);
    });
  });

  group('the app under DVDisplayScale', () {
    Future<Size> pumpAt(WidgetTester tester, Size logical, {List<Offset> taps = const []}) async {
      tester.view.physicalSize = logical;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late Size seen;
      await tester.pumpWidget(DVDisplayScale(
        child: Builder(builder: (BuildContext context) {
          seen = MediaQuery.sizeOf(context);
          return const Directionality(textDirection: TextDirection.ltr, child: SizedBox.expand());
        }),
      ));
      return seen;
    }

    testWidgets('a desktop keeps its own size and nothing is wrapped', (tester) async {
      expect(await pumpAt(tester, const Size(1366, 900)), const Size(1366, 900));
      expect(find.byType(FittedBox), findsNothing);
      expect(DV.Platform.screen.uiScale, 1);
    });

    testWidgets('a 4K panel lays the app out at 1280 x 720 and fills the screen', (tester) async {
      expect(await pumpAt(tester, const Size(3840, 2160)), const Size(1280, 720));
      final Rect drawn = tester.getRect(find.byType(SizedBox).last);
      expect(drawn, const Rect.fromLTWH(0, 0, 3840, 2160), reason: 'drawn three times larger, edge to edge');
      expect(DV.Platform.screen.uiScale, 3);
      expect(DV.Platform.screen.screenClass, DVScreenClass.billboard);
    });

    testWidgets('a watch lays the app out at 320 x 320', (tester) async {
      expect(await pumpAt(tester, const Size(240, 240)), const Size(320, 320));
    });

    testWidgets('taps land where they are drawn', (tester) async {
      tester.view.physicalSize = const Size(3840, 2160);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      int pressed = 0;
      await tester.pumpWidget(DVDisplayScale(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => pressed++,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      ));
      await tester.tapAt(const Offset(250, 250)); // inside 0..300 on screen
      expect(pressed, 1);
      await tester.tapAt(const Offset(350, 350)); // outside it
      expect(pressed, 1);
    });

    testWidgets('an app can turn scaling off in code', (tester) async {
      DV.Platform.screen.scaling = const DVDisplayScaling.off();
      addTearDown(() => DV.Platform.screen.scaling = const DVDisplayScaling.auto());
      expect(await pumpAt(tester, const Size(3840, 2160)), const Size(3840, 2160));
    });
  });

  testWidgets('DV.run draws the application through DVDisplayScale', (tester) async {
    tester.view.physicalSize = const Size(3840, 2160);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(dvResetApplicationEntryForTest);
    late Size seen;
    await dvRunApplication(const [], root: () => Builder(builder: (BuildContext context) {
          seen = MediaQuery.sizeOf(context);
          return const SizedBox();
        }));
    await tester.pump();
    expect(seen, const Size(1280, 720));
  });
}
