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

  group('what the widget gallery calls it', () {
    test('is the title the widget declared', () {
      // configurationDisplayName is the line under the preview in the
      // gallery, and it was the identifier -- a route segment. "next-shift"
      // among an iPhone's widgets reads as somebody's debugging left in.
      final String swift = dvAppleHomeWidgetSource(const <DVHomeWidgetSpec>[
        DVHomeWidgetSpec(
          id: 'next-shift',
          name: 'NextShiftWidget',
          route: '/widgets/next-shift',
          title: 'Next shift',
        ),
      ], 'dartvel');

      expect(swift, contains('.configurationDisplayName("Next shift")'));
    });

    test('falls back to the identifier when there is no title', () {
      // An empty display name is a widget nobody can find in the gallery.
      final String swift = dvAppleHomeWidgetSource(_widgets, 'dartvel');

      expect(swift, contains('.configurationDisplayName("today")'));
    });
  });

  group('the data the application leaves it', () {
    test('is read from the key the application writes', () {
      // The two halves are in different languages and different processes,
      // and nothing brings them together until somebody puts the widget on
      // their home screen. The Swift built its own key by interpolating the
      // kind; the Dart runtime derives one from core. Two rules that agree
      // today is a widget showing its placeholder for ever the first time
      // either is touched, with nothing to see at either end.
      final String swift = dvAppleHomeWidgetSource(_widgets, 'dartvel');

      expect(swift, contains('"${dvHomeWidgetDataKey('today')}"'));
      expect(swift, contains('"${dvHomeWidgetDataKey('next-shift')}"'));
    });

    test('and the group is the one the entitlements name', () {
      // The App Group is derived from the application's bundle id in three
      // places -- the entitlement, the build setting and the runtime that
      // writes -- and a fourth spelling would be a correctly signed widget
      // reading an empty container.
      expect(dvAppleAppGroup('com.example.shop'),
          dvHomeWidgetAppGroup('com.example.shop'));
    });
  });

  _sdkFloor();
}

// ---------------------------------------------------------------------------
// The SDK the extension is actually built against.
//
// Found by building it. The target declares a deployment floor of iOS 14 --
// WidgetKit's own, and low enough to reach the devices a widget is most
// likely to be on -- and the first generated view used .foregroundStyle,
// which is iOS 17, and .secondary as a ShapeStyle, which is iOS 15. Xcode
// refused both, having happily accepted the project file and the target: the
// splice was right and the Swift was not.
//
// A string test cannot know what Apple shipped when, so this is not a general
// availability check. It is a list of the specific symbols that have already
// been wrong once, which is the class of mistake that comes back when
// somebody edits the view and reaches for the modern spelling.

void _sdkFloor() {
  group('the generated view against its deployment target', () {
    const List<String> tooNew = <String>[
      // iOS 17 / macOS 14. `.foregroundColor` is deprecated there and still
      // compiles, which is the right trade for a floor of 14.
      'foregroundStyle',
      // iOS 16.
      'AnyLayout',
      'Gauge',
      // iOS 15, and the reason the first version failed twice over.
      'foregroundStyle(.secondary)',
    ];

    test('it uses nothing newer than the target it is built with', () {
      final String swift = dvAppleHomeWidgetSource(_widgets, 'dartvel');

      for (final String symbol in tooNew) {
        expect(swift, isNot(contains(symbol)), reason: symbol);
      }
    });

    test('the one modern API it does use is behind an availability check', () {
      // containerBackground is the exception and has to be: a widget built
      // against the iOS 17 SDK that does not declare its background is drawn
      // without one. It cannot simply be called, because the deployment
      // target is older than the API.
      final String swift = dvAppleHomeWidgetSource(_widgets, 'dartvel');

      expect(swift, contains('#available(iOS 17.0'));

      // The call site, not the first mention of the name: the comment above
      // the helper explains why it is there, and a search for the bare word
      // finds that instead -- which is how this assertion first failed
      // against code that was correct.
      final int guard = swift.indexOf('#available(iOS 17.0');
      final int call = swift.indexOf('self.containerBackground(');
      expect(call, greaterThan(0), reason: 'it has to actually be called');
      expect(call, greaterThan(guard),
          reason: 'the call must sit inside the check, not before it');
    });

    test('the two branches are a view builder, not one opaque type', () {
      // A function returning `some View` has one opaque type, and the two
      // branches here do not have it: containerBackground and padding return
      // different ones, so Swift refused the file with "branches have
      // mismatching types" and every iOS build failed at the Xcode step --
      // after Dart, after generation, after everything this repository tests.
      // @ViewBuilder is what lets a function return either.
      final String swift = dvAppleHomeWidgetSource(_widgets, 'dartvel');

      final int surface = swift.indexOf('func dartvelWidgetSurface()');
      expect(surface, greaterThan(0));
      expect(
        swift.substring(0, surface),
        endsWith('@ViewBuilder\n    '),
      );
    });
  });
}
