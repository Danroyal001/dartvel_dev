/// The Android half of a declared kiosk: a lock-task launcher.
///
/// The specification's production path is an artifact that "starts in kiosk
/// at boot", with "no window of unlocked UI at startup", and it names what
/// that is on each platform -- eLinux images, Windows assigned access, and
/// Android lock-task launchers.
///
/// A lock-task launcher is two things in the manifest and nothing in the
/// Dart. The application has to be a HOME activity, or pressing home leaves
/// it; and it has to carry a device-admin receiver, or `dpm set-device-owner`
/// has nothing to point at and lock task shows the "pin this screen?" dialog
/// to somebody who is not there. Neither can be added at run time, which is
/// why this is a build step and not an API.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The kiosk a project declares, as far as the Android build cares.
class DVAndroidKiosk {
  const DVAndroidKiosk({required this.enabled, this.scope = 'device'});

  final bool enabled;

  /// `device` or `display`. Only a device-scope kiosk becomes the home
  /// screen: a display-scope one owns a window, and taking the whole device
  /// from its user would be a different feature wearing the same word.
  final String scope;

  bool get ownsTheDevice => enabled && scope == 'device';

  /// What `dartvel.kiosk` in the project at [root] says.
  static DVAndroidKiosk of(String root) {
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return const DVAndroidKiosk(enabled: false);
    try {
      final Object? document = loadYaml(pubspec.readAsStringSync());
      final Object? dartvel = document is Map ? document['dartvel'] : null;
      final Object? kiosk = dartvel is Map ? dartvel['kiosk'] : null;
      if (kiosk is! Map) return const DVAndroidKiosk(enabled: false);
      return DVAndroidKiosk(
        enabled: kiosk['enabled'] == true,
        scope: '${kiosk['scope'] ?? 'device'}',
      );
    } catch (_) {
      // A pubspec that will not parse is the build's own message to give.
      return const DVAndroidKiosk(enabled: false);
    }
  }
}

const String _markStart = '        <!-- dartvel.kiosk: begin -->';
const String _markEnd = '        <!-- dartvel.kiosk: end -->';

/// The receiver class, named once so the manifest, the Java file and the
/// device-owner command cannot come to disagree about it.
const String dvAndroidDeviceAdminClass = 'DartvelDeviceAdminReceiver';

/// [manifest] with the kiosk block in it, or without it when there is no
/// kiosk.
///
/// The block is marked, so a second build replaces it rather than adding
/// another: a manifest with two receivers is one the packager refuses, from a
/// build that succeeded.
String dvAndroidKioskManifest(String manifest, DVAndroidKiosk kiosk) {
  final RegExp block = RegExp(
      '\n${RegExp.escape(_markStart)}.*?${RegExp.escape(_markEnd)}',
      dotAll: true);
  final String stripped = manifest.replaceAll(block, '');
  if (!kiosk.ownsTheDevice) return stripped;

  final StringBuffer out = StringBuffer()
    ..writeln(_markStart)
    ..writeln('        <!-- A device-scope kiosk is the home screen. Without')
    ..writeln('             this the home button leaves the application, which')
    ..writeln('             is the one thing a kiosk exists to prevent. -->')
    ..writeln('        <activity-alias')
    ..writeln('            android:name=".DartvelKioskHome"')
    ..writeln('            android:targetActivity=".MainActivity"')
    ..writeln('            android:exported="true">')
    ..writeln('            <intent-filter>')
    ..writeln('                <action android:name="android.intent.action.MAIN"/>')
    ..writeln('                <category android:name="android.intent.category.HOME"/>')
    ..writeln('                <category android:name="android.intent.category.DEFAULT"/>')
    ..writeln('            </intent-filter>')
    ..writeln('        </activity-alias>')
    ..writeln('        <!-- The component dpm set-device-owner points at.')
    ..writeln('             Without one, lock task shows the "pin this screen?"')
    ..writeln('             dialog to nobody. -->')
    ..writeln('        <receiver')
    ..writeln('            android:name=".$dvAndroidDeviceAdminClass"')
    ..writeln('            android:exported="true"')
    ..writeln('            android:permission="android.permission.BIND_DEVICE_ADMIN">')
    ..writeln('            <meta-data')
    ..writeln('                android:name="android.app.device_admin"')
    ..writeln('                android:resource="@xml/dartvel_device_admin"/>')
    ..writeln('            <intent-filter>')
    ..writeln('                <action android:name="android.app.action.DEVICE_ADMIN_ENABLED"/>')
    ..writeln('            </intent-filter>')
    ..writeln('        </receiver>')
    ..write(_markEnd);

  // Inside <application>, before its closing tag: a receiver declared outside
  // it is a manifest the packager refuses.
  final int close = stripped.lastIndexOf('    </application>');
  if (close < 0) return stripped;
  return '${stripped.substring(0, close)}${out.toString()}\n${stripped.substring(close)}';
}

/// The receiver itself.
///
/// It does nothing, and that is correct: a device-admin receiver exists so
/// the system has a component to make the owner. The behaviour is lock task,
/// which is the Activity's.
String dvAndroidDeviceAdminSource(String package) => '''
package $package;

// GENERATED by dartvel build. A device-scope kiosk needs a device-admin
// component for `dpm set-device-owner` to point at; without one, lock task
// shows the "pin this screen?" dialog on a device nobody is standing at.
//
// It does nothing on purpose. The enforcement is lock task mode, which is the
// Activity's, and Dartvel holds it from Dart through JNI.
import android.app.admin.DeviceAdminReceiver;

public class $dvAndroidDeviceAdminClass extends DeviceAdminReceiver {
}
''';

/// The policy XML the receiver's meta-data points at.
String dvAndroidDeviceAdminPolicy() => '''
<?xml version="1.0" encoding="utf-8"?>
<!-- GENERATED by dartvel build. An empty file is accepted by aapt and
     rejected by the device: set-device-owner fails with a message about the
     admin component, hours after the build that wrote it. -->
<device-admin xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-policies>
        <force-lock/>
    </uses-policies>
</device-admin>
''';
