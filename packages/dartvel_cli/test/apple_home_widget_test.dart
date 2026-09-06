// The Apple half of a home widget.
//
// Android is packaged: a declared @DVHomeWidget becomes an AppWidgetProvider,
// its metadata, a layout and a manifest receiver. iOS and macOS were left
// with the Dart half only -- a page at /widgets/<id> and an entry in a
// support table -- which is the same promise the Android side used to make
// and did not keep.
//
// WidgetKit is not Android's widget under another name, and the differences
// are the ones that fail quietly:
//
//   - a widget extension is a separate bundle, and iOS loads it only if its
//     Info.plist names the WidgetKit extension point. A bundle without that
//     line builds, installs, and never appears in the widget gallery.
//   - the app and the widget are different processes with different
//     containers. Without an App Group they share nothing, and a widget that
//     reads its own empty container renders a placeholder forever.
//   - the tap is a widgetURL, and a widget whose URL is the app's own scheme
//     with no route opens the home screen. That is a shortcut, not a widget,
//     and it is what Android did before deepLinks.initial landed.
import 'package:dartvel_cli/src/build/apple_home_widget.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const List<DVHomeWidgetSpec> _widgets = <DVHomeWidgetSpec>[
  DVHomeWidgetSpec(id: 'today', name: 'TodayWidget', route: '/widgets/today'),
  DVHomeWidgetSpec(
      id: 'next-shift', name: 'NextShiftWidget', route: '/widgets/next-shift'),
];

void main() {
  group('the extension bundle', () {
    test('declares the WidgetKit extension point', () {
      // Without NSExtensionPointIdentifier the target compiles, links,
      // embeds and installs, and the widget never appears in the gallery.
      // There is no error anywhere: the system simply never asks the bundle
      // for anything.
      final String plist = dvAppleHomeWidgetInfoPlist();

      expect(plist, contains('NSExtensionPointIdentifier'));
      expect(plist, contains('com.apple.widgetkit-extension'));
    });

    test('is a bundle, not an application', () {
      // CFBundlePackageType APPL on an extension is a bundle iOS refuses at
      // install time, with a message about the containing app.
      expect(dvAppleHomeWidgetInfoPlist(), contains('XPC!'));
    });
  });

  group('the App Group', () {
    test('is per application, so two Dartvel apps do not share a container', () {
      // The same mistake as an Android provider authority: a constant here
      // means the second app installed reads the first one's data, or is
      // refused the entitlement outright.
      expect(dvAppleAppGroup('com.example.shop'),
          isNot(dvAppleAppGroup('com.example.depot')));
      expect(dvAppleAppGroup('com.example.shop'), startsWith('group.'));
      expect(dvAppleAppGroup('com.example.shop'), contains('com.example.shop'));
    });

    test('is claimed by the entitlements the extension is signed with', () {
      // An extension without the group entitlement reads its own container,
      // which is empty, and renders the placeholder forever -- on somebody's
      // home screen, not in the build.
      final String entitlements =
          dvAppleHomeWidgetEntitlements('group.com.example.shop.dartvel');

      expect(entitlements, contains('com.apple.security.application-groups'));
      expect(entitlements, contains('group.com.example.shop.dartvel'));
    });
  });

  group('the generated Swift', () {
    test('bundles every declared widget, and only those', () {
      // A WidgetBundle that omits one leaves a declared widget with nothing
      // on the platform, which is the promise this exists to stop making.
      final String swift = dvAppleHomeWidgetSource(_widgets, 'dartvel');

      expect(swift, contains('TodayWidget()'));
      expect(swift, contains('NextShiftWidget()'));
      expect(swift, contains('@main'));
      expect(swift, contains('WidgetBundle'));
    });

    test('each widget has a kind, and no two share one', () {
      // WidgetKit addresses a widget by its kind string. Two widgets with
      // one kind is a reload of the wrong widget and a timeline written into
      // the wrong one, with nothing said about it.
      final String swift = dvAppleHomeWidgetSource(_widgets, 'dartvel');

      expect(dvAppleWidgetKind('today'), isNot(dvAppleWidgetKind('next-shift')));
      expect(swift, contains('kind: "${dvAppleWidgetKind('today')}"'));
      expect(swift, contains('kind: "${dvAppleWidgetKind('next-shift')}"'));
    });

    test('an id that is not a Swift identifier still compiles', () {
      // Widget ids come from a class name in Dart and may carry hyphens.
      // "struct next-shiftWidget" is a Swift file that does not parse, from
      // a build that reported success up to the point Xcode ran.
      final String swift = dvAppleHomeWidgetSource(_widgets, 'dartvel');

      expect(swift, isNot(contains('struct next-shift')));
      expect(swift, contains('struct NextShiftWidget'));
    });

    test('the tap opens the route, not the application', () {
      // The whole of what the specification asks of a home widget: that it
      // can launch and navigate to a page. A widgetURL with no path opens
      // the home route, which looks like it works.
      final String swift = dvAppleHomeWidgetSource(_widgets, 'dartvel');

      expect(swift, contains('dartvel://widget/widgets/today'));
      expect(swift, contains('dartvel://widget/widgets/next-shift'));
      expect(swift, contains('.widgetURL('));
    });

    test('it reads the shared container, not its own', () {
      // UserDefaults(suiteName:) is the group container. Plain
      // UserDefaults.standard in an extension is the extension's own, which
      // the application never writes to.
      final String swift = dvAppleHomeWidgetSource(_widgets, 'dartvel');

      expect(swift, contains('UserDefaults(suiteName:'));
      expect(swift, isNot(contains('UserDefaults.standard')));
    });

    test('a timeline that never refreshes is not written', () {
      // A provider returning .never is a widget that shows what it showed
      // the day it was placed. It is a legitimate policy and it is not the
      // right default for an application's data.
      final String swift = dvAppleHomeWidgetSource(_widgets, 'dartvel');

      expect(swift, contains('policy:'));
      expect(swift, isNot(contains('policy: .never')));
    });

    test('no widgets is no bundle, rather than an empty one', () {
      // An @main WidgetBundle with no widgets is an extension that installs
      // and offers nothing, which is worse than not being there: it takes a
      // slot in the gallery.
      expect(dvAppleHomeWidgetSource(const <DVHomeWidgetSpec>[], 'dartvel'),
          isEmpty);
    });
  });

  group('the scheme it is given', () {
    test('is the application\'s, not a constant', () {
      // Two Dartvel applications on one device both registering dartvel://
      // is a race the second one loses, silently.
      final String swift = dvAppleHomeWidgetSource(_widgets, 'shopapp');

      expect(swift, contains('shopapp://widget/widgets/today'));
      expect(swift, isNot(contains('dartvel://widget')));
    });
  });
}
