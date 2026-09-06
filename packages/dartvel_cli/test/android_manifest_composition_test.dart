// The three manifest writers, in the order `dartvel build android` runs
// them.
//
// Each is tested on its own against a pristine manifest, and each passes.
// The build does not run them on a pristine manifest: it runs the context
// provider, then the kiosk, then the home widgets, each on what the last one
// wrote. Nothing checked that, and the symptom of it being wrong is not a
// build failure -- it is an APK that installs, launches, looks right, and is
// missing a component nobody notices until `dpm set-device-owner` says
// "Unknown admin" on a device in a lobby.
//
// The manifest here is the shape Flutter actually creates, not a minimal
// one, because the splices anchor on text in it.
import 'package:dartvel_cli/src/build/android_context_provider.dart';
import 'package:dartvel_cli/src/build/android_home_widget.dart';
import 'package:dartvel_cli/src/build/android_kiosk_manifest.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String _flutterManifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="dartvel_example"
        android:name="\${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
''';

/// The build's own order: context provider, kiosk, home widgets.
String _build(
  String manifest, {
  required bool kiosk,
  List<DVHomeWidgetSpec> widgets = const <DVHomeWidgetSpec>[],
}) {
  String out = dvAndroidContextProviderManifest(manifest);
  out = dvAndroidKioskManifest(
      out,
      kiosk
          ? const DVAndroidKiosk(enabled: true, scope: 'device')
          : const DVAndroidKiosk(enabled: false, scope: 'device'));
  out = dvAndroidHomeWidgetManifest(out, widgets);
  return out;
}

void main() {
  group('all three writers, in build order', () {
    test('the kiosk receiver survives the writers that run after it', () {
      // The home-widget writer runs last and strips its own marked block
      // from whatever it is given. A project with no home widgets still
      // calls it, and if its strip or its splice touched the kiosk block
      // the receiver would leave the manifest between being written and
      // being packaged -- which is a build that succeeds and a device that
      // says "Unknown admin".
      final String out = _build(_flutterManifest, kiosk: true);

      expect(out, contains('DartvelDeviceAdminReceiver'),
          reason: 'the receiver must still be declared');
      expect(out, contains('android.app.action.DEVICE_ADMIN_ENABLED'),
          reason: 'without the filter the system cannot find the admin');
      expect(out, contains('android.permission.BIND_DEVICE_ADMIN'));
      expect(out, contains('android.intent.category.HOME'));
    });

    test('the Context provider survives the writers that run after it', () {
      // Every Android binding Dartvel has reaches the platform through this
      // provider's Context. It is written first, so it is the one with two
      // chances to be removed.
      final String out = _build(_flutterManifest, kiosk: true);

      expect(out, contains('dev.dartvel.jni.DartvelContext'));
      expect(out, contains(r'${applicationId}.dartvelcontext'));
    });

    test('every block lands inside <application>', () {
      // A provider or receiver declared after </application> is a manifest
      // the packager refuses -- but only some packagers, and a merger that
      // accepts it can drop the stray node instead.
      final String out = _build(_flutterManifest,
          kiosk: true,
          widgets: const <DVHomeWidgetSpec>[
            DVHomeWidgetSpec(id: 'today', name: 'Today', route: '/'),
          ]);

      final int close = out.indexOf('</application>');
      expect(close, greaterThan(0));
      for (final String needle in <String>[
        'DartvelDeviceAdminReceiver',
        'DartvelKioskHome',
        'dev.dartvel.jni.DartvelContext',
        'TodayProvider',
      ]) {
        expect(out.indexOf(needle), lessThan(close), reason: needle);
        expect(out.indexOf(needle), greaterThan(0), reason: needle);
      }
    });

    test('two builds leave one of each, not two', () {
      // Android refuses a package that declares the same authority or the
      // same receiver twice, and the refusal names neither the build that
      // wrote it nor the one before.
      final String once = _build(_flutterManifest, kiosk: true);
      final String twice = _build(once, kiosk: true);

      for (final String needle in <String>[
        'DartvelDeviceAdminReceiver',
        'dev.dartvel.jni.DartvelContext',
        'DartvelKioskHome',
      ]) {
        expect(needle.allMatches(twice).length,
            needle.allMatches(once).length,
            reason: needle);
      }
    });

    test('turning the kiosk off leaves the Context provider alone', () {
      // The two blocks are independent, and a project that stops being a
      // kiosk must not lose the Context every other binding goes through.
      final String kiosked = _build(_flutterManifest, kiosk: true);
      final String plain = _build(kiosked, kiosk: false);

      expect(plain, isNot(contains('DartvelDeviceAdminReceiver')));
      expect(plain, contains('dev.dartvel.jni.DartvelContext'));
    });
  });
}
