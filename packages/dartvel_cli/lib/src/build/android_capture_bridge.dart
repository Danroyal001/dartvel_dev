/// The Activity plumbing every permission-gated Android API needs.
///
/// A Context is not an Activity, and that sentence is the whole of this
/// file. `DartvelContext` holds an application Context, which is enough to
/// reach a system service and nothing like enough for the four things this
/// slice of the platform is made of: `requestPermissions` is an Activity
/// method, `onRequestPermissionsResult` is delivered only to an Activity,
/// `startActivityForResult` is an Activity method, and `onActivityResult`
/// comes back to the same one.
///
/// Dartvel does not own the application's `MainActivity`. Flutter generates
/// it, developers edit it, and a framework that rewrote it would lose
/// whatever was there. So the callbacks arrive at an Activity of Dartvel's
/// own: transparent, excluded from recents, started with one operation in
/// its Intent, finished the moment the answer is in. The Dart side never
/// sees it.
///
/// Everything here is Java that ships into the generated Android project
/// rather than tooling, which is what the one-language rule draws the line
/// at. The reason it is Java at all is the reason `allowLockTask` is: the
/// work is arrays, cursors, a `Looper` and a callback interface, and each of
/// those is a jnigen binding that has to exist and be correct before Dart
/// can express it. Four guesses at generated member names were wrong four
/// times. Java that `javac` checks at build time is not a guess.
library dartvel_cli.build.android_capture_bridge;

import 'package:dartvel_core/dartvel.dart'
    show
        DVAndroidPermission,
        DVAndroidPermissionGroup,
        dvAndroidCaptureAuthoritySuffix,
        dvAndroidPermissions;

/// Where each generated file goes, relative to the project root.
const String dvAndroidCaptureBridgePath =
    'android/app/src/main/java/dev/dartvel/jni/DartvelActivityBridge.java';
const String dvAndroidBridgeActivityPath =
    'android/app/src/main/java/dev/dartvel/jni/DartvelBridgeActivity.java';
const String dvAndroidCaptureFilesPath =
    'android/app/src/main/java/dev/dartvel/jni/DartvelCaptureFiles.java';

/// The permission names a project asks for, from `dartvel.android.permissions`.
///
/// Declared rather than inferred. What an application asks for at run time is
/// not knowable at build time, and a framework that declared every
/// permission it can request would put `READ_CONTACTS` on the store listing
/// of a torch application.
List<String> dvAndroidRequestedPermissions(Object? dartvelSection) {
  final Object? android =
      dartvelSection is Map ? dartvelSection['android'] : null;
  final Object? listed = android is Map ? android['permissions'] : null;
  if (listed is! List) return const <String>[];
  final List<String> out = <String>[];
  for (final Object? entry in listed) {
    final String name = '$entry'.trim();
    // Unknown names are kept rather than dropped, so the build can say so.
    // Dropping one silently is a manifest missing exactly the line the
    // developer wrote the pubspec entry to get.
    if (name.isNotEmpty && !out.contains(name)) out.add(name);
  }
  return out;
}

/// The names in [requested] that Dartvel has no Android permission for.
List<String> dvAndroidUnknownPermissions(List<String> requested) => <String>[
      for (final String name in requested)
        if (!dvAndroidPermissions.containsKey(name)) name,
    ];

/// One `<uses-permission>` line per Android permission [requested] needs.
///
/// Every API level's spelling, not just this one's: the manifest is read by
/// whichever device installs the APK, and `maxSdkVersion` is how a manifest
/// says "this one is for the old phones" without asking the new ones for it.
List<String> dvAndroidUsesPermissions(List<String> requested) {
  final List<String> lines = <String>[];
  for (final String name in requested) {
    final DVAndroidPermissionGroup? group = dvAndroidPermissions[name];
    if (group == null) continue;
    for (final DVAndroidPermission permission in group.permissions) {
      final StringBuffer line = StringBuffer()
        ..write('    <uses-permission android:name="${permission.name}"');
      if (permission.maxSdk != null) {
        line.write('\n        android:maxSdkVersion="${permission.maxSdk}"');
      }
      line.write('/>');
      final String rendered = line.toString();
      if (!lines.contains(rendered)) lines.add(rendered);
    }
  }
  return lines;
}

const String _markStart = '    <!-- dartvel.capture: start -->\n';
const String _markEnd = '    <!-- dartvel.capture: end -->\n';
const String _appMarkStart = '        <!-- dartvel.capture.app: start -->\n';
const String _appMarkEnd = '        <!-- dartvel.capture.app: end -->\n';

/// [manifest] with the permissions [requested] declares, the bridge Activity
/// and the capture provider.
///
/// Marked and rewritten rather than appended, because a second build that
/// added a second copy of the Activity is a package Android refuses to
/// install -- and the error it gives names the component rather than the
/// build that wrote it twice.
String dvAndroidCaptureManifest(String manifest, List<String> requested) {
  String out = _replaceBlock(manifest, _markStart, _markEnd);
  out = _replaceBlock(out, _appMarkStart, _appMarkEnd);

  final List<String> permissions = dvAndroidUsesPermissions(requested);
  if (permissions.isNotEmpty) {
    // Above <application>, which is where a uses-permission belongs. Inside
    // it the manifest merger drops it and says nothing anyone reads.
    final int application = out.indexOf('<application');
    if (application >= 0) {
      final int lineStart = out.lastIndexOf('\n', application) + 1;
      final StringBuffer block = StringBuffer()
        ..write(_markStart)
        ..writeln('    <!-- What dartvel.android.permissions in pubspec.yaml')
        ..writeln('         asks for. A permission requested at run time and')
        ..writeln('         missing here is refused instantly, with no')
        ..writeln('         dialog, and reads exactly like a refusal. -->');
      for (final String line in permissions) {
        block.writeln(line);
      }
      block.write(_markEnd);
      out = '${out.substring(0, lineStart)}$block${out.substring(lineStart)}';
    }
  }

  final int close = out.indexOf('</application>');
  if (close < 0) return out;
  final int lineStart = out.lastIndexOf('\n', close) + 1;
  final StringBuffer block = StringBuffer()
    ..write(_appMarkStart)
    ..writeln('        <!-- Receives onRequestPermissionsResult and')
    ..writeln('             onActivityResult, which are delivered to an')
    ..writeln('             Activity and to nothing else. Transparent, so')
    ..writeln('             the application stays on screen behind it. -->')
    ..writeln('        <activity')
    ..writeln('            android:name="dev.dartvel.jni.'
        'DartvelBridgeActivity"')
    ..writeln('            android:theme="@android:style/'
        'Theme.Translucent.NoTitleBar"')
    // Nothing outside this application has any business starting it.
    ..writeln('            android:exported="false"')
    ..writeln('            android:excludeFromRecents="true"')
    // Rotating the phone while the camera is open must not restart it and
    // lose the request the Activity is holding.
    ..writeln('            android:configChanges="orientation|screenSize|'
        'keyboardHidden"')
    ..writeln('            android:noHistory="false"/>')
    ..writeln('        <!-- Somewhere for a camera application to write a')
    ..writeln('             photo. A file:// URI has thrown')
    ..writeln('             FileUriExposedException since API 24, so the')
    ..writeln('             capture has to be handed a content:// one. -->')
    ..writeln('        <provider')
    ..writeln('            android:name="dev.dartvel.jni.DartvelCaptureFiles"')
    ..writeln(r'            android:authorities="${applicationId}'
        '$dvAndroidCaptureAuthoritySuffix"')
    ..writeln('            android:exported="false"')
    // The camera application reaches it through the grant on the Intent,
    // which is why it can stay unexported.
    ..writeln('            android:grantUriPermissions="true"/>')
    ..write(_appMarkEnd);

  return '${out.substring(0, lineStart)}$block${out.substring(lineStart)}';
}

String _replaceBlock(String source, String start, String end) {
  final int existing = source.indexOf(start);
  if (existing < 0) return source;
  final int stop = source.indexOf(end, existing);
  if (stop < 0) return source;
  return source.substring(0, existing) + source.substring(stop + end.length);
}

/// The Java that resolves one of Dartvel's permission names.
///
/// Generated from the same table the manifest is generated from, so the two
/// cannot disagree. They did not have to be one table -- and a hand-written
/// second copy is how an application ends up requesting a permission its own
/// manifest never declared, which Android refuses without a dialog.
String _resolveCases() {
  final StringBuffer out = StringBuffer();
  for (final MapEntry<String, DVAndroidPermissionGroup> entry
      in dvAndroidPermissions.entries) {
    out.writeln('      case "${entry.key}":');
    for (final DVAndroidPermission permission in entry.value.permissions) {
      final List<String> guards = <String>[
        if (permission.minSdk != null) 'sdk >= ${permission.minSdk}',
        if (permission.maxSdk != null) 'sdk <= ${permission.maxSdk}',
      ];
      if (guards.isEmpty) {
        out.writeln('        out.add("${permission.name}");');
      } else {
        out.writeln('        if (${guards.join(" && ")}) '
            'out.add("${permission.name}");');
      }
    }
    out.writeln('        break;');
  }
  return out.toString().trimRight();
}

String _anyOfCases() {
  final List<String> names = <String>[
    for (final MapEntry<String, DVAndroidPermissionGroup> entry
        in dvAndroidPermissions.entries)
      if (entry.value.anyOf) entry.key,
  ];
  if (names.isEmpty) return '    return false;';
  return '    return ${names.map((String n) => 'logical.equals("$n")').join(
        '\n        || ',
      )};';
}

/// The bridge itself: what Dart calls, by name, over JNI.
String dvAndroidCaptureBridgeSource() => '''
package dev.dartvel.jni;

// GENERATED by dartvel build. The Activity plumbing behind the
// permission-gated platform bindings.
//
// Dart reaches every method here by name through JClass.forName, the same
// way it reaches DartvelContext. Renaming one, or changing its signature,
// is a lookup that fails on a device and nowhere else -- so the monorepo
// test test/unit/android_jni_signature_test.dart reads this source and the
// Dart that calls it and fails when they stop agreeing.
//
// Results are collected here and polled from Dart rather than pushed back
// over a callback. A callback into Dart from an arbitrary Android thread is
// the part of JNI most likely to be subtly wrong, and this needs none of it:
// the answer to "has the person finished with the camera" is a string that
// either exists yet or does not.

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.ContactsContract;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.json.JSONArray;
import org.json.JSONObject;

public final class DartvelActivityBridge {
  private DartvelActivityBridge() {}

  public static final String EXTRA_ID = "dev.dartvel.id";
  public static final String EXTRA_OP = "dev.dartvel.op";
  public static final String EXTRA_ARG = "dev.dartvel.arg";

  private static final Map<Integer, String> sResults =
      new HashMap<Integer, String>();
  private static int sNext = 1;

  /// Why nothing can be started, or null when something can.
  ///
  /// Separate from every operation's own errors so that "this APK was built
  /// with plain flutter build" reads differently from "the person said no".
  public static String state() {
    if (DartvelContext.context() == null) {
      return "Android has not created the Context provider yet";
    }
    return null;
  }

  /// What Android says about one of Dartvel's permission names, as JSON.
  ///
  /// Carries `declared` beside `granted` deliberately. Requesting a
  /// permission the manifest does not declare is refused immediately, with
  /// no dialog shown and the same result code a person tapping Deny
  /// produces. Without this key those two are the same answer, and the fix
  /// for one of them is a line in pubspec.yaml that nobody knows to add.
  public static String granted(String logical) {
    JSONObject out = new JSONObject();
    try {
      out.put("permission", logical);
      Context context = DartvelContext.context();
      if (context == null) {
        out.put("error", "there is no application Context yet");
        return out.toString();
      }
      String[] names = resolve(logical);
      if (names == null) {
        out.put("error", "Dartvel has no permission called " + logical);
        return out.toString();
      }
      JSONArray required = new JSONArray();
      boolean everyOneDeclared = true;
      boolean anyGranted = names.length == 0;
      boolean everyOneGranted = true;
      for (int i = 0; i < names.length; i++) {
        required.put(names[i]);
        if (!declared(context, names[i])) everyOneDeclared = false;
        if (held(context, names[i])) {
          anyGranted = true;
        } else {
          everyOneGranted = false;
        }
      }
      out.put("required", required);
      out.put("declared", names.length == 0 || everyOneDeclared);
      out.put("granted", anyOf(logical) ? anyGranted : everyOneGranted);
    } catch (Throwable error) {
      // Reported rather than thrown. A JNI call that throws leaves the
      // exception pending on the Dart side, where it surfaces later and
      // somewhere else.
      try {
        out.put("error", String.valueOf(error));
      } catch (Throwable ignored) {
        return "{}";
      }
    }
    return out.toString();
  }

  /// Starts [op] and returns the id its answer will arrive under.
  ///
  /// Negative means it never started: -1 for no Context, -2 for an operation
  /// this build does not have. Both are worth telling apart from an
  /// operation that started and was refused.
  public static int begin(String op, String argument) {
    Context context = DartvelContext.context();
    if (context == null) return -1;
    int id;
    synchronized (sResults) {
      id = sNext++;
    }
    String arg = argument == null ? "" : argument;
    if ("contacts".equals(op)) {
      startContacts(id, arg);
      return id;
    }
    if ("location".equals(op)) {
      startLocation(id, arg);
      return id;
    }
    if (!"permissions".equals(op) && !"camera".equals(op)
        && !"media".equals(op)) {
      return -2;
    }
    final Intent intent = new Intent(context, DartvelBridgeActivity.class);
    intent.putExtra(EXTRA_ID, id);
    intent.putExtra(EXTRA_OP, op);
    intent.putExtra(EXTRA_ARG, arg);
    final Activity activity = DartvelContext.activity();
    if (activity != null) {
      // From the Activity in front, so the transparent one joins the task
      // the person is already in. Started from the application Context it
      // would need FLAG_ACTIVITY_NEW_TASK and would appear as a second entry
      // in recents.
      //
      // On the main thread, because Dart calls this from the Flutter UI
      // thread and Activity methods are not promised to be safe anywhere
      // else.
      activity.runOnUiThread(new Runnable() {
        public void run() {
          activity.startActivity(intent);
        }
      });
    } else {
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
      context.startActivity(intent);
    }
    return id;
  }

  /// The answer to [id], once, or null while it has not arrived.
  ///
  /// Removed as it is read. Nothing asks twice, and a map that grew for the
  /// life of the process would hold every photo path an application ever
  /// captured.
  public static String poll(int id) {
    synchronized (sResults) {
      return sResults.remove(Integer.valueOf(id));
    }
  }

  static void complete(int id, String json) {
    synchronized (sResults) {
      sResults.put(Integer.valueOf(id), json);
    }
  }

  static void fail(int id, String reason) {
    JSONObject out = new JSONObject();
    try {
      out.put("error", reason);
    } catch (Throwable ignored) {
      complete(id, "{}");
      return;
    }
    complete(id, out.toString());
  }

  /// The Android permissions [logical] needs on this device, or null when
  /// Dartvel has no such name.
  ///
  /// Null and empty are different answers: empty means nothing has to be
  /// asked for, which is true of the clipboard, and null means the name is
  /// a typo. Answering "granted" to a typo is how an application ships
  /// believing it holds a permission it never asked for.
  static String[] resolve(String logical) {
    int sdk = Build.VERSION.SDK_INT;
    List<String> out = new ArrayList<String>();
    switch (logical) {
${_resolveCases()}
      default:
        return null;
    }
    return out.toArray(new String[out.size()]);
  }

  /// Whether holding one of the group is enough.
  static boolean anyOf(String logical) {
${_anyOfCases()}
  }

  /// Whether the manifest asks for [permission] at all.
  static boolean declared(Context context, String permission) {
    try {
      PackageManager packages = context.getPackageManager();
      PackageInfo info = packages.getPackageInfo(
          context.getPackageName(), PackageManager.GET_PERMISSIONS);
      String[] requested = info.requestedPermissions;
      if (requested == null) return false;
      for (int i = 0; i < requested.length; i++) {
        if (permission.equals(requested[i])) return true;
      }
      return false;
    } catch (Throwable error) {
      return false;
    }
  }

  /// Whether [permission] is held right now.
  static boolean held(Context context, String permission) {
    if (Build.VERSION.SDK_INT < 23) {
      // Before Marshmallow every declared permission is granted by
      // installing the application, and there is no runtime dialog to show.
      return declared(context, permission);
    }
    return context.checkSelfPermission(permission)
        == PackageManager.PERMISSION_GRANTED;
  }

  // --- contacts -----------------------------------------------------------

  /// The address book, on a thread of its own.
  ///
  /// Not on the caller's: Dart calls this from the Flutter UI thread, and a
  /// cursor over a few thousand contacts there is a frame budget spent on a
  /// database.
  private static void startContacts(final int id, final String argument) {
    new Thread(new Runnable() {
      public void run() {
        Context context = DartvelContext.context();
        if (context == null) {
          fail(id, "there is no application Context");
          return;
        }
        if (!held(context, "android.permission.READ_CONTACTS")) {
          fail(id, "READ_CONTACTS is not granted");
          return;
        }
        Cursor cursor = null;
        try {
          int limit = 0;
          try {
            limit = new JSONObject(argument).optInt("limit", 0);
          } catch (Throwable ignored) {
            limit = 0;
          }
          cursor = context.getContentResolver().query(
              ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
              new String[] {
                ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER,
              },
              null,
              null,
              ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC");
          JSONArray people = new JSONArray();
          Set<String> seen = new LinkedHashSet<String>();
          if (cursor != null) {
            while (cursor.moveToNext()) {
              String contactId = cursor.getString(0);
              // One row per number, so a contact with a mobile and a work
              // number arrives twice. The first is kept; a list with the
              // same person in it three times is not an address book.
              if (contactId != null && !seen.add(contactId)) continue;
              JSONObject person = new JSONObject();
              person.put("id", contactId == null ? "" : contactId);
              person.put("name", nonNull(cursor.getString(1)));
              person.put("phone", nonNull(cursor.getString(2)));
              people.put(person);
              if (limit > 0 && people.length() >= limit) break;
            }
          }
          JSONObject out = new JSONObject();
          out.put("contacts", people);
          complete(id, out.toString());
        } catch (Throwable error) {
          fail(id, "the contacts query failed: " + error);
        } finally {
          if (cursor != null) cursor.close();
        }
      }
    }).start();
  }

  private static String nonNull(String value) {
    return value == null ? "" : value;
  }

  // --- location -----------------------------------------------------------

  /// Where the device is.
  ///
  /// The last known fix when there is a recent one, and a single update when
  /// there is not. Last-known alone is the usual shortcut and it is wrong
  /// often enough to matter: a phone that has not been asked for a position
  /// since it was last rebooted has none, and an API that answers zero
  /// there puts the person in the Gulf of Guinea.
  private static void startLocation(final int id, final String argument) {
    final Context context = DartvelContext.context();
    if (context == null) {
      fail(id, "there is no application Context");
      return;
    }
    int parsedAge = 120;
    int parsedTimeout = 20;
    try {
      JSONObject options = new JSONObject(argument);
      parsedAge = options.optInt("maxAgeSeconds", 120);
      parsedTimeout = options.optInt("timeoutSeconds", 20);
    } catch (Throwable ignored) {
      // The defaults above.
    }
    final int maxAgeSeconds = parsedAge;
    final int timeoutSeconds = parsedTimeout;
    final Handler handler = new Handler(Looper.getMainLooper());
    handler.post(new Runnable() {
      public void run() {
        if (!held(context, "android.permission.ACCESS_FINE_LOCATION")
            && !held(context, "android.permission.ACCESS_COARSE_LOCATION")) {
          fail(id, "neither location permission is granted");
          return;
        }
        LocationManager manager = (LocationManager)
            context.getSystemService(Context.LOCATION_SERVICE);
        if (manager == null) {
          fail(id, "this device has no location service");
          return;
        }
        Location best = null;
        List<String> providers = manager.getProviders(true);
        for (int i = 0; i < providers.size(); i++) {
          Location candidate = null;
          try {
            candidate = manager.getLastKnownLocation(providers.get(i));
          } catch (SecurityException error) {
            continue;
          }
          if (candidate == null) continue;
          if (best == null || candidate.getTime() > best.getTime()) {
            best = candidate;
          }
        }
        long age = best == null
            ? Long.MAX_VALUE
            : (System.currentTimeMillis() - best.getTime()) / 1000L;
        if (best != null && age <= maxAgeSeconds) {
          complete(id, describe(best, age));
          return;
        }
        if (providers.isEmpty()) {
          fail(id, "every location provider is turned off");
          return;
        }
        final Location stale = best;
        final LocationManager located = manager;
        final boolean[] answered = new boolean[] {false};
        final LocationListener[] listener = new LocationListener[1];
        listener[0] = new LocationListener() {
          public void onLocationChanged(Location location) {
            if (answered[0]) return;
            answered[0] = true;
            located.removeUpdates(listener[0]);
            complete(id, describe(location, 0));
          }

          public void onStatusChanged(String provider, int status,
              Bundle extras) {}

          public void onProviderEnabled(String provider) {}

          public void onProviderDisabled(String provider) {}
        };
        try {
          for (int i = 0; i < providers.size(); i++) {
            located.requestLocationUpdates(
                providers.get(i), 0L, 0f, listener[0], Looper.getMainLooper());
          }
        } catch (SecurityException error) {
          fail(id, "the location permission was revoked mid-request");
          return;
        }
        handler.postDelayed(new Runnable() {
          public void run() {
            if (answered[0]) return;
            answered[0] = true;
            located.removeUpdates(listener[0]);
            if (stale != null) {
              // Old, and said to be old. A stale fix is usually the right
              // answer indoors, and a caller that cares can look at the age
              // rather than be told nothing.
              complete(id, describe(stale,
                  (System.currentTimeMillis() - stale.getTime()) / 1000L));
              return;
            }
            fail(id, "no location arrived within " + timeoutSeconds
                + " seconds and the device has no earlier fix");
          }
        }, timeoutSeconds * 1000L);
      }
    });
  }

  private static String describe(Location location, long ageSeconds) {
    JSONObject out = new JSONObject();
    try {
      out.put("latitude", location.getLatitude());
      out.put("longitude", location.getLongitude());
      out.put("accuracy", location.hasAccuracy() ? location.getAccuracy() : -1);
      out.put("altitude", location.hasAltitude() ? location.getAltitude() : 0);
      out.put("provider", nonNull(location.getProvider()));
      out.put("ageSeconds", ageSeconds);
      out.put("timestamp", location.getTime());
    } catch (Throwable error) {
      return "{}";
    }
    return out.toString();
  }
}
''';

/// The Activity the results come back to.
String dvAndroidBridgeActivitySource() => '''
package dev.dartvel.jni;

// GENERATED by dartvel build. The Activity that receives
// onRequestPermissionsResult and onActivityResult.
//
// It exists because those two callbacks are delivered to an Activity and to
// nothing else, and because the application's MainActivity belongs to the
// developer. This one is transparent, is excluded from recents, does the one
// thing its Intent asked for, and finishes.

import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.MediaStore;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;

import org.json.JSONArray;
import org.json.JSONObject;

public final class DartvelBridgeActivity extends Activity {
  private static final int PERMISSIONS = 4001;
  private static final int CAMERA = 4002;
  private static final int MEDIA = 4003;

  private int id = -1;
  private String[] asked = new String[0];
  private String logical = "";
  private File photo;

  @Override
  protected void onCreate(Bundle saved) {
    super.onCreate(saved);
    Intent intent = getIntent();
    id = intent.getIntExtra(DartvelActivityBridge.EXTRA_ID, -1);
    String op = intent.getStringExtra(DartvelActivityBridge.EXTRA_OP);
    String argument = intent.getStringExtra(DartvelActivityBridge.EXTRA_ARG);
    if (saved != null) {
      // Recreated after Android killed the process behind the camera. The
      // result map went with it, so there is nobody left to answer.
      finish();
      return;
    }
    try {
      if ("permissions".equals(op)) {
        startPermissions(argument);
      } else if ("camera".equals(op)) {
        startCamera();
      } else if ("media".equals(op)) {
        startMedia(argument);
      } else {
        answer(error("unknown operation " + op));
      }
    } catch (Throwable failure) {
      answer(error(String.valueOf(failure)));
    }
  }

  private void startPermissions(String argument) throws Exception {
    JSONObject options = new JSONObject(argument);
    logical = options.optString("permission", "");
    String[] names = DartvelActivityBridge.resolve(logical);
    if (names == null) {
      answer(error("Dartvel has no permission called " + logical));
      return;
    }
    List<String> missing = new ArrayList<String>();
    for (int i = 0; i < names.length; i++) {
      if (!DartvelActivityBridge.held(this, names[i])) {
        missing.add(names[i]);
      }
    }
    if (missing.isEmpty() || Build.VERSION.SDK_INT < 23) {
      // Nothing to ask for, or a device from before runtime permissions
      // existed. Either way the answer is what the manifest already got.
      answer(permissionResult(names));
      return;
    }
    asked = missing.toArray(new String[missing.size()]);
    requestPermissions(asked, PERMISSIONS);
  }

  @Override
  public void onRequestPermissionsResult(int request, String[] permissions,
      int[] results) {
    super.onRequestPermissionsResult(request, permissions, results);
    if (request != PERMISSIONS) return;
    answer(permissionResult(DartvelActivityBridge.resolve(logical)));
  }

  /// What the platform says now, rather than what the dialog returned.
  ///
  /// The result array is not the whole answer: a permission that was already
  /// held is not in it, and one refused permanently comes back denied with
  /// no dialog having been shown. Asking the package manager afterwards is
  /// one source for both.
  private String permissionResult(String[] names) {
    JSONObject out = new JSONObject();
    try {
      out.put("permission", logical);
      boolean everyOneDeclared = true;
      boolean anyGranted = names == null || names.length == 0;
      boolean everyOneGranted = true;
      boolean blocked = false;
      JSONArray required = new JSONArray();
      if (names != null) {
        for (int i = 0; i < names.length; i++) {
          required.put(names[i]);
          if (!DartvelActivityBridge.declared(this, names[i])) {
            everyOneDeclared = false;
          }
          if (DartvelActivityBridge.held(this, names[i])) {
            anyGranted = true;
          } else {
            everyOneGranted = false;
            // "Don't ask again", or a policy that forbids it. Android says
            // so by refusing to show a rationale for a permission that is
            // not held, and the difference decides whether an application
            // should ask again or send the person to Settings.
            if (Build.VERSION.SDK_INT >= 23
                && !shouldShowRequestPermissionRationale(names[i])) {
              blocked = true;
            }
          }
        }
      }
      out.put("required", required);
      out.put("declared", names == null || names.length == 0
          || everyOneDeclared);
      out.put("granted", DartvelActivityBridge.anyOf(logical)
          ? anyGranted : everyOneGranted);
      out.put("blocked", blocked && !everyOneGranted);
    } catch (Throwable failure) {
      return error(String.valueOf(failure));
    }
    return out.toString();
  }

  private void startCamera() {
    File directory = new File(getCacheDir(), "dartvel-capture");
    directory.mkdirs();
    photo = new File(directory,
        "capture-" + System.currentTimeMillis() + ".jpg");
    Uri target = DartvelCaptureFiles.uriFor(this, photo);
    Intent capture = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
    capture.putExtra(MediaStore.EXTRA_OUTPUT, target);
    // Without both grants the camera application is handed a URI it is not
    // allowed to open, and returns RESULT_CANCELED with no explanation --
    // which is indistinguishable from the person pressing back.
    capture.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
    capture.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
    if (capture.resolveActivity(getPackageManager()) == null) {
      answer(error("this device has no camera application"));
      return;
    }
    startActivityForResult(capture, CAMERA);
  }

  private void startMedia(String argument) throws Exception {
    JSONObject options = new JSONObject(argument);
    String kind = options.optString("type", "image");
    boolean multiple = options.optBoolean("multiple", false);
    // ACTION_OPEN_DOCUMENT rather than the gallery: it is the system picker,
    // it needs no permission at all, and what it returns is readable
    // whether the file is on the device or in a cloud provider.
    Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT);
    pick.addCategory(Intent.CATEGORY_OPENABLE);
    if ("image".equals(kind)) {
      pick.setType("image/*");
    } else if ("video".equals(kind)) {
      pick.setType("video/*");
    } else if ("audio".equals(kind)) {
      pick.setType("audio/*");
    } else {
      pick.setType("*/*");
    }
    if (multiple) {
      pick.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
    }
    startActivityForResult(pick, MEDIA);
  }

  @Override
  protected void onActivityResult(int request, int result, Intent data) {
    super.onActivityResult(request, result, data);
    if (result != RESULT_OK) {
      // The person pressed back. Not an error, and not the same as a
      // failure: an empty list is what a cancelled picker means everywhere
      // else in Dartvel.
      answer(cancelled());
      return;
    }
    try {
      if (request == CAMERA) {
        answer(cameraResult());
      } else if (request == MEDIA) {
        answer(mediaResult(data));
      } else {
        answer(cancelled());
      }
    } catch (Throwable failure) {
      answer(error(String.valueOf(failure)));
    }
  }

  private String cameraResult() throws Exception {
    if (photo == null || !photo.exists() || photo.length() == 0) {
      // RESULT_OK and nothing written. Some camera applications answer this
      // way when they were handed a URI they could not open, and a caller
      // told "here is your photo" would read an empty file.
      return error("the camera reported success and wrote no file");
    }
    JSONObject item = new JSONObject();
    item.put("path", photo.getAbsolutePath());
    item.put("name", photo.getName());
    item.put("type", "image");
    item.put("bytes", photo.length());
    JSONArray items = new JSONArray();
    items.put(item);
    JSONObject out = new JSONObject();
    out.put("items", items);
    return out.toString();
  }

  private String mediaResult(Intent data) throws Exception {
    List<Uri> chosen = new ArrayList<Uri>();
    if (data != null) {
      ClipData clip = data.getClipData();
      if (clip != null) {
        for (int i = 0; i < clip.getItemCount(); i++) {
          Uri uri = clip.getItemAt(i).getUri();
          if (uri != null) chosen.add(uri);
        }
      } else if (data.getData() != null) {
        chosen.add(data.getData());
      }
    }
    if (chosen.isEmpty()) return cancelled();

    File directory = new File(getCacheDir(), "dartvel-picked");
    directory.mkdirs();
    JSONArray items = new JSONArray();
    for (int i = 0; i < chosen.size(); i++) {
      Uri uri = chosen.get(i);
      String name = displayName(uri);
      // Copied out rather than handed over as a content:// URI. Every
      // Dartvel media API answers with a path, and a URI in a field called
      // path is a string that opens nowhere.
      File file = new File(directory, System.currentTimeMillis() + "-" + name);
      copy(uri, file);
      JSONObject item = new JSONObject();
      item.put("path", file.getAbsolutePath());
      item.put("name", name);
      item.put("mimeType", nonNull(getContentResolver().getType(uri)));
      item.put("bytes", file.length());
      items.put(item);
    }
    JSONObject out = new JSONObject();
    out.put("items", items);
    return out.toString();
  }

  private void copy(Uri uri, File target) throws Exception {
    InputStream input = getContentResolver().openInputStream(uri);
    if (input == null) throw new IllegalStateException("could not open " + uri);
    OutputStream output = new FileOutputStream(target);
    try {
      byte[] buffer = new byte[8192];
      int read;
      while ((read = input.read(buffer)) > 0) {
        output.write(buffer, 0, read);
      }
      output.flush();
    } finally {
      try {
        input.close();
      } catch (Throwable ignored) {
        // Closing a stream that is already gone.
      }
      try {
        output.close();
      } catch (Throwable ignored) {
        // The same.
      }
    }
  }

  private String displayName(Uri uri) {
    Cursor cursor = null;
    try {
      cursor = getContentResolver().query(uri, null, null, null, null);
      if (cursor != null && cursor.moveToFirst()) {
        int column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
        if (column >= 0) {
          String name = cursor.getString(column);
          if (name != null && name.length() > 0) return sanitise(name);
        }
      }
    } catch (Throwable ignored) {
      // A provider that answers no metadata. The fallback below is a name.
    } finally {
      if (cursor != null) cursor.close();
    }
    String last = uri.getLastPathSegment();
    return last == null ? "file" : sanitise(last);
  }

  /// A file name with nothing in it that can leave the directory.
  ///
  /// The name comes from whichever application answered the picker, so it is
  /// somebody else's string. A provider returning "../../databases/app.db"
  /// would otherwise have this copy a chosen file over the application's own
  /// data.
  private String sanitise(String name) {
    String out = name.replace("/", "_").replace("\\\\", "_");
    while (out.startsWith(".")) {
      out = out.substring(1);
    }
    if (out.length() == 0) return "file";
    return out.length() > 120 ? out.substring(out.length() - 120) : out;
  }

  private String cancelled() {
    JSONObject out = new JSONObject();
    try {
      out.put("cancelled", true);
      out.put("items", new JSONArray());
    } catch (Throwable ignored) {
      return "{}";
    }
    return out.toString();
  }

  private String error(String reason) {
    JSONObject out = new JSONObject();
    try {
      out.put("error", reason);
    } catch (Throwable ignored) {
      return "{}";
    }
    return out.toString();
  }

  private String nonNull(String value) {
    return value == null ? "" : value;
  }

  private void answer(String json) {
    if (id >= 0) DartvelActivityBridge.complete(id, json);
    finish();
    // No animation. This Activity is plumbing and a fade would look like the
    // application flickering.
    overridePendingTransition(0, 0);
  }
}
''';

/// The provider that hands a camera application a file to write into.
String dvAndroidCaptureFilesSource() => '''
package dev.dartvel.jni;

// GENERATED by dartvel build. Somewhere for a camera application to put a
// photo.
//
// androidx.core.content.FileProvider does this, and depending on it would
// mean editing the application's Gradle files to add a library that may or
// may not already be on the classpath. This serves one directory in the
// cache and needs nothing.
//
// A file:// URI would need none of this and has thrown
// FileUriExposedException since API 24.

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileNotFoundException;

public final class DartvelCaptureFiles extends ContentProvider {
  /// The directory this provider serves, and the only one it will.
  static File directory(Context context) {
    return new File(context.getCacheDir(), "dartvel-capture");
  }

  /// The content:// URI for a file in that directory.
  public static Uri uriFor(Context context, File file) {
    return Uri.parse("content://" + context.getPackageName()
        + "$dvAndroidCaptureAuthoritySuffix/" + Uri.encode(file.getName()));
  }

  /// The file a URI names, or null when it names something outside the
  /// directory.
  ///
  /// The check is not decoration. The camera application is handed a grant
  /// on this provider, and a URI it built itself with ".." in the path would
  /// otherwise reach any file the application can open.
  private File resolve(Uri uri) {
    Context context = getContext();
    if (context == null) return null;
    String name = uri.getLastPathSegment();
    if (name == null || name.length() == 0) return null;
    if (name.contains("/") || name.contains("..")) return null;
    return new File(directory(context), name);
  }

  @Override
  public boolean onCreate() {
    return true;
  }

  @Override
  public ParcelFileDescriptor openFile(Uri uri, String mode)
      throws FileNotFoundException {
    File file = resolve(uri);
    if (file == null) throw new FileNotFoundException("not this provider's");
    int flags = ParcelFileDescriptor.MODE_READ_WRITE
        | ParcelFileDescriptor.MODE_CREATE;
    if (mode != null && mode.contains("t")) {
      flags = flags | ParcelFileDescriptor.MODE_TRUNCATE;
    }
    return ParcelFileDescriptor.open(file, flags);
  }

  @Override
  public Cursor query(Uri uri, String[] projection, String selection,
      String[] selectionArgs, String sortOrder) {
    // Camera applications ask for the name and the size before writing.
    File file = resolve(uri);
    if (file == null) return null;
    MatrixCursor cursor = new MatrixCursor(new String[] {
      OpenableColumns.DISPLAY_NAME,
      OpenableColumns.SIZE,
    });
    cursor.addRow(new Object[] {file.getName(), Long.valueOf(file.length())});
    return cursor;
  }

  @Override
  public String getType(Uri uri) {
    return "image/jpeg";
  }

  @Override
  public Uri insert(Uri uri, ContentValues values) {
    return null;
  }

  @Override
  public int delete(Uri uri, String selection, String[] selectionArgs) {
    File file = resolve(uri);
    if (file == null || !file.exists()) return 0;
    return file.delete() ? 1 : 0;
  }

  @Override
  public int update(Uri uri, ContentValues values, String selection,
      String[] selectionArgs) {
    return 0;
  }
}
''';
