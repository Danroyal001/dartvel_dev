// FCM on Android reaches a Dartvel application through Java the build writes,
// a Gradle dependency, a manifest service and four string resources. Each is
// silent when wrong: a service missing from the manifest receives nothing and
// raises nothing, a dependency added twice is a duplicate-class failure on
// the second build, and a stale one left behind after `dartvel.push.android`
// was removed ships Firebase to users of an app that no longer sends push.
import 'package:dartvel_cli/src/build/android_push_bridge.dart';
import 'package:dartvel_core/dartvel.dart'
    show
        DVFcmAppConfig,
        dvAndroidFirebaseMessagingLibrary,
        dvAndroidPushBridgeClass,
        dvAndroidPushServiceClass;
import 'package:test/test.dart';

const DVFcmAppConfig fcm = DVFcmAppConfig(
  projectId: 'demo-project',
  appId: '1:1234567890:android:abc123',
  apiKey: 'AIzaSyDemoKey',
  senderId: '1234567890',
);

const String manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="app">
        <activity android:name=".MainActivity"/>
    </application>
</manifest>
''';

const String groovy = '''
plugins {
    id "com.android.application"
}
android {
    namespace "com.example.app"
}
''';

const String kotlin = '''
plugins {
    id("com.android.application")
}
android {
    namespace = "com.example.app"
}
''';

void main() {
  group('the manifest service', () {
    test('is declared inside <application>, not exported, for MESSAGING_EVENT',
        () {
      final String out = dvAndroidPushManifest(manifest, include: true);
      expect(out, contains('android:name="$dvAndroidPushServiceClass"'));
      expect(out, contains('android:exported="false"'));
      expect(out, contains('com.google.firebase.MESSAGING_EVENT'));
      expect(out.indexOf(dvAndroidPushServiceClass),
          lessThan(out.indexOf('</application>')));
    });

    test('is written once however often the build runs', () {
      final String once = dvAndroidPushManifest(manifest, include: true);
      expect(dvAndroidPushManifest(once, include: true), once);
      expect(RegExp(RegExp.escape(dvAndroidPushServiceClass)).allMatches(once),
          hasLength(1));
    });

    test('comes back out when push is no longer declared', () {
      final String with_ = dvAndroidPushManifest(manifest, include: true);
      expect(dvAndroidPushManifest(with_, include: false), manifest);
    });

    test('leaves a manifest with no <application> alone', () {
      expect(dvAndroidPushManifest('<manifest/>', include: true), '<manifest/>');
    });
  });

  group('the Gradle dependency', () {
    test('is added once to Groovy and Kotlin scripts', () {
      final String g = dvAndroidGradleWithPush(groovy,
          include: true, kotlinScript: false);
      expect(g, contains('implementation "$dvAndroidFirebaseMessagingLibrary"'));
      expect(dvAndroidGradleWithPush(g, include: true, kotlinScript: false), g);
      final String k = dvAndroidGradleWithPush(kotlin,
          include: true, kotlinScript: true);
      expect(k, contains('implementation("$dvAndroidFirebaseMessagingLibrary")'));
      expect(dvAndroidGradleWithPush(k, include: true, kotlinScript: true), k);
    });

    test('comes back out exactly', () {
      final String with_ = dvAndroidGradleWithPush(groovy,
          include: true, kotlinScript: false);
      expect(dvAndroidGradleWithPush(with_, include: false, kotlinScript: false),
          groovy);
    });
  });

  group('the Firebase resources', () {
    test('are the four names FirebaseOptions.fromResource reads', () {
      final String xml = dvAndroidFirebaseResources(fcm);
      expect(xml, contains('<string name="google_app_id"'
          ' translatable="false">1:1234567890:android:abc123</string>'));
      expect(xml, contains('name="google_api_key"'));
      expect(xml, contains('>AIzaSyDemoKey<'));
      expect(xml, contains('name="gcm_defaultSenderId"'));
      expect(xml, contains('name="project_id"'));
      expect(xml, contains('>demo-project<'));
    });

    test('escape markup, so a value cannot break out of its element', () {
      final String xml = dvAndroidFirebaseResources(const DVFcmAppConfig(
        projectId: 'p</string><string name="x">',
        appId: "a'b",
        apiKey: 'a&b',
        senderId: '1',
      ));
      expect(xml, isNot(contains('</string><string name="x">')));
      expect(xml, contains('&lt;/string&gt;'));
      expect(xml, contains('a&amp;b'));
      // An apostrophe is an escape in Android string resources.
      expect(xml, contains(r"a\'b"));
    });
  });

  group('the bridge', () {
    final String bridge = dvAndroidPushBridgeSource();
    final String service = dvAndroidPushServiceSource();

    test('is the class Dart looks up', () {
      expect(dvAndroidPushBridgePath,
          endsWith('${dvAndroidPushBridgeClass.split('/').last}.java'));
      expect(bridge, contains('public final class DartvelPush'));
      expect(bridge, contains('package dev.dartvel.jni;'));
    });

    test('offers the calls DVDevicePushProvider makes', () {
      for (final String method in <String>[
        'public static String start(',
        'public static String poll(',
        'public static String drainMessages(',
      ]) {
        expect(bridge, contains(method), reason: method);
      }
    });

    test('speaks the message shape the Dart side reads', () {
      for (final String key in <String>[
        '"id"', '"title"', '"body"', '"data"', '"receivedAt"', '"opened"',
      ]) {
        expect(bridge, contains(key), reason: key);
      }
    });

    test('keeps what arrived while no Dart was running', () {
      // A data message wakes the process with no Flutter engine. Held only
      // in memory it is lost with the process.
      expect(bridge, contains('SharedPreferences'));
    });

    test('the service hands every message and token to the bridge', () {
      expect(service, contains('extends FirebaseMessagingService'));
      expect(service, contains('onMessageReceived'));
      expect(service, contains('onNewToken'));
      expect(service, contains('DartvelPush.'));
    });

    test('never logs a token or a payload', () {
      for (final String source in <String>[bridge, service]) {
        expect(source, isNot(contains('Log.')));
        expect(source, isNot(contains('System.out')));
      }
    });
  });

  group('dartvel.push.android in the pubspec', () {
    test('adds the notifications permission the OS asks for on API 33', () {
      expect(
          dvAndroidPushPermissions(declared: true, requested: <String>['camera']),
          <String>['camera', 'notifications']);
      expect(
          dvAndroidPushPermissions(
              declared: true, requested: <String>['notifications']),
          <String>['notifications']);
      expect(dvAndroidPushPermissions(declared: false, requested: <String>['camera']),
          <String>['camera']);
    });
  });
}
