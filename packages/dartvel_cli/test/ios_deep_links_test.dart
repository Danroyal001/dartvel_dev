// Where a widget's tap lands on iOS.
//
// The generated widget's tap is a widgetURL carrying the route the widget was
// generated for. WidgetKit delivers it to the containing application, and on
// iOS nothing in Dartvel was listening: the app opened at its home route,
// which looks like it worked and is a shortcut rather than a widget. It is
// the same bug Android had before deepLinks.initial landed there.
//
// The URL arrives at the app delegate, so the build has to write into
// AppDelegate.swift -- a file the developer owns. That constrains what may be
// written: marked so a second build replaces rather than repeats, surgical so
// nothing the template already does is disturbed, and reversible so a project
// that stops wanting it is put back exactly as it was.
import 'package:dartvel_cli/src/build/ios_deep_links.dart';
import 'package:test/test.dart';

const String _appDelegate = '''
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
''';

void main() {
  group('what it writes', () {
    test('it catches a cold launch, where the URL is in the launch options',
        () {
      // A widget tapped on a device where the app is not running is the
      // common case, and it is the one that does not arrive at open(url:).
      final String out = dvIosAppDelegate(_appDelegate, enabled: true);

      expect(out, contains('willFinishLaunchingWithOptions'));
      expect(out, contains('.url'));
    });

    test('it catches a warm launch, where it arrives as an open', () {
      // The app already running is the other half, and an implementation
      // with only one of them works in whichever case the developer tried.
      final String out = dvIosAppDelegate(_appDelegate, enabled: true);

      expect(out, contains('open url: URL'));
    });

    test('it does not override what the template already overrides', () {
      // Two overrides of one method is a Swift file that does not compile.
      // The template implements didFinishLaunchingWithOptions, so this must
      // not.
      final String out = dvIosAppDelegate(_appDelegate, enabled: true);

      expect('didFinishLaunchingWithOptions'.allMatches(out).length,
          'didFinishLaunchingWithOptions'.allMatches(_appDelegate).length);
    });

    test('it calls super, so the plugins still see the launch', () {
      // An override that swallows the call is a Flutter application whose
      // plugins never receive a URL they were registered for.
      final String out = dvIosAppDelegate(_appDelegate, enabled: true);

      expect(out, contains('super.application('));
    });

    test('it writes where the Dart side reads', () {
      // One key, named once. Two spellings is a launch that is captured and
      // never read, with nothing to see at either end.
      final String out = dvIosAppDelegate(_appDelegate, enabled: true);

      expect(out, contains(dvIosLaunchUrlKey));
    });
  });

  group('writing into a file somebody owns', () {
    test('a second build does not add it twice', () {
      // Two copies of one override is a Swift file that does not compile,
      // from a build that succeeded.
      final String once = dvIosAppDelegate(_appDelegate, enabled: true);
      final String twice = dvIosAppDelegate(once, enabled: true);

      expect(twice, once);
    });

    test('turning it off puts the file back exactly as it was', () {
      final String once = dvIosAppDelegate(_appDelegate, enabled: true);

      expect(dvIosAppDelegate(once, enabled: false), _appDelegate);
    });

    test('a project that never wanted it is untouched', () {
      expect(dvIosAppDelegate(_appDelegate, enabled: false), _appDelegate);
    });

    test('a delegate it cannot read is left alone rather than mangled', () {
      // Somebody has rewritten AppDelegate.swift and there is no class body
      // this recognises. Writing into it anyway would break a file the
      // developer owns, for a feature they can add by hand in four lines.
      const String rewritten = 'import Flutter\n// nothing this knows\n';

      expect(dvIosAppDelegate(rewritten, enabled: true), rewritten);
    });
  });
}
