// What happens after an app icon's quick action is chosen.
//
// Every platform hands the action over as the launch link
// `dartvel:///<route>`. A cold launch reads it once after the first frame. A
// warm one is different per platform: Android recreates the activity for a
// static shortcut (it is started with NEW_TASK | CLEAR_TASK), which is a
// cold launch again, but iOS calls the running application's delegate, so
// the link is stored and has to be read when the application comes back to
// the foreground. Without that the quick action brings the application up
// on whatever page it was left on.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(DVAppLaunch.resetForTest);

  test('a quick action link opens its route', () {
    const DVAppShortcut shortcut = DVAppShortcut(id: 'new-order', title: 'New order', route: '/orders/new?from=icon');
    expect(DVAppLaunch.routeFor(shortcut.launchLink), '/orders/new?from=icon');
  });

  testWidgets('on iOS a link stored while running is opened on resume', (WidgetTester tester) async {
    String? stored;
    final List<String> opened = <String>[];
    final DVLaunchLinkFollower follower = DVAppLaunch.followLaunchLinks(
      link: () async {
        final String? value = stored;
        stored = null; // read and cleared, as the iOS binding does
        return value;
      },
      open: (String route) async => opened.add(route),
      platform: TargetPlatform.iOS,
    );
    addTearDown(follower.dispose);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(opened, isEmpty, reason: 'launched from its own icon: nothing to open');

    stored = 'dartvel:///orders/new';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(opened, <String>['/orders/new']);

    // A resume with nothing new stored opens nothing again.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(opened, <String>['/orders/new']);
  });

  testWidgets('the cold launch link is opened after the first frame', (WidgetTester tester) async {
    final List<String> opened = <String>[];
    final DVLaunchLinkFollower follower = DVAppLaunch.followLaunchLinks(
      link: () async => 'dartvel:///search',
      open: (String route) async => opened.add(route),
      platform: TargetPlatform.android,
    );
    addTearDown(follower.dispose);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(opened, <String>['/search']);
  });

  testWidgets('Android does not re-read on resume: its intent is not consumed', (WidgetTester tester) async {
    int asked = 0;
    final DVLaunchLinkFollower follower = DVAppLaunch.followLaunchLinks(
      link: () async {
        asked++;
        return 'dartvel:///search';
      },
      open: (String route) async {},
      platform: TargetPlatform.android,
    );
    addTearDown(follower.dispose);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(asked, 1, reason: 'the same intent would reopen the page on every resume');
  });
}
