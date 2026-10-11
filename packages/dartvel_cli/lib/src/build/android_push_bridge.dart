/// Firebase Cloud Messaging for `PushNotifications` on Android, as Java the
/// build writes into the generated Android project.
///
/// Written only when `pubspec.yaml` declares `dartvel.push.android.fcm`. An
/// application that sends no push gets no Firebase library, no service in its
/// manifest and no extra permission on its store listing.
///
/// Four generated pieces, all marked so the next build replaces them rather
/// than adding to them (Android refuses a package that declares one service
/// twice, and Gradle refuses one dependency twice):
///
///  * `DartvelPush`, which Dart calls over JNI to fetch the token, change
///    topics and drain the messages that arrived;
///  * `DartvelMessagingService`, which Firebase starts to deliver a message
///    and which does nothing but hand it to `DartvelPush`;
///  * the manifest `<service>` Firebase finds that service through;
///  * the four string resources `FirebaseOptions.fromResource` reads, which
///    is what the google-services plugin would generate from
///    `google-services.json`. Writing them directly means no JSON file to
///    commit, no plugin, and nothing in the project to hand-edit.
///
/// The shape is the billing bridge's and the capture bridge's, for the
/// reason they give: a callback into Dart from whichever Android thread
/// Firebase picks is the part of JNI hardest to get right and hardest to see
/// going wrong. Dart polls; Java never calls into it.
library dartvel_cli.build.android_push_bridge;

import 'package:dartvel_core/dartvel.dart'
    show
        DVFcmAppConfig,
        dvAndroidFirebaseMessagingLibrary,
        dvAndroidPushBridgeClass,
        dvAndroidPushServiceClass;

const String _javaRoot = 'android/app/src/main/java/';

/// Where the bridge is written, relative to the project root.
const String dvAndroidPushBridgePath =
    '$_javaRoot$dvAndroidPushBridgeClass.java';

/// Where the Firebase service is written.
const String dvAndroidPushServicePath =
    '${_javaRoot}dev/dartvel/jni/DartvelMessagingService.java';

/// The string resources FCM initialises from.
const String dvAndroidFirebaseResourcesPath =
    'android/app/src/main/res/values/dartvel_firebase.xml';

/// The permissions the project's declaration implies, given the [requested]
/// ones from `dartvel.android.permissions`.
///
/// Android 13 and later show no notification without `POST_NOTIFICATIONS`
/// being granted at run time, and cannot ask for it unless it is declared. A
/// project that declared push and forgot the permission would build, register
/// a token, and never show a banner.
List<String> dvAndroidPushPermissions({
  required bool declared,
  required List<String> requested,
}) {
  if (!declared || requested.contains('notifications')) return requested;
  return <String>[...requested, 'notifications'];
}

const String _manifestStart = '        <!-- dartvel.push: start -->\n';
const String _manifestEnd = '        <!-- dartvel.push: end -->\n';

/// [manifest] with the Firebase service declared inside `<application>` when
/// [include], and without it otherwise.
String dvAndroidPushManifest(String manifest, {required bool include}) {
  final int existing = manifest.indexOf(_manifestStart);
  final String stripped = existing < 0
      ? manifest
      : manifest.substring(0, existing) +
          manifest.substring(
              manifest.indexOf(_manifestEnd, existing) + _manifestEnd.length);
  if (!include) return stripped;

  final int close = stripped.indexOf('</application>');
  if (close < 0) return stripped;
  final int lineStart = stripped.lastIndexOf('\n', close) + 1;

  final StringBuffer out = StringBuffer()
    ..write(_manifestStart)
    ..writeln('        <!-- Firebase Cloud Messaging delivers a message by')
    ..writeln('             starting this service, which queues it for Dart. -->')
    ..writeln('        <service')
    ..writeln('            android:name="$dvAndroidPushServiceClass"')
    // Only Firebase starts it, through the intent filter. An exported service
    // is one any application can feed messages to.
    ..writeln('            android:exported="false">')
    ..writeln('            <intent-filter>')
    ..writeln('                <action android:name="com.google.firebase.MESSAGING_EVENT"/>')
    ..writeln('            </intent-filter>')
    ..writeln('        </service>')
    ..write(_manifestEnd);

  return '${stripped.substring(0, lineStart)}$out${stripped.substring(lineStart)}';
}

const String _gradleStart = '// dartvel.push: start';
const String _gradleEnd = '// dartvel.push: end';

/// [gradle] (the app module's build script) with the Firebase Cloud
/// Messaging dependency when [include], and without it otherwise.
///
/// A marked block of its own for the reason the billing dependency is one:
/// Gradle merges any number of `dependencies` blocks, Flutter's template has
/// none to splice into, and a block of our own is one a later build can find
/// and take out exactly.
String dvAndroidGradleWithPush(
  String gradle, {
  required bool include,
  required bool kotlinScript,
}) {
  final String stripped = _stripGradle(gradle);
  if (!include) return stripped;
  final String dependency = kotlinScript
      ? 'implementation("$dvAndroidFirebaseMessagingLibrary")'
      : 'implementation "$dvAndroidFirebaseMessagingLibrary"';
  final String separator = stripped.endsWith('\n') ? '' : '\n';
  return '$stripped$separator'
      '\n$_gradleStart\n'
      '// Firebase Cloud Messaging, for PushNotifications. Written by dartvel\n'
      '// build from dartvel.push.android in pubspec.yaml; removed when that is.\n'
      'dependencies {\n'
      '    $dependency\n'
      '}\n'
      '$_gradleEnd\n';
}

String _stripGradle(String gradle) {
  final int start = gradle.indexOf(_gradleStart);
  if (start < 0) return gradle;
  final int end = gradle.indexOf(_gradleEnd, start);
  if (end < 0) return gradle;
  int cut = start;
  if (cut >= 2 && gradle.substring(cut - 2, cut) == '\n\n') cut -= 1;
  int after = end + _gradleEnd.length;
  if (after < gradle.length && gradle[after] == '\n') after += 1;
  return gradle.substring(0, cut) + gradle.substring(after);
}

/// The string resources `FirebaseOptions.fromResource` reads.
String dvAndroidFirebaseResources(DVFcmAppConfig fcm) => '''
<?xml version="1.0" encoding="utf-8"?>
<!-- GENERATED by dartvel build from dartvel.push.android.fcm. Do not edit: the
     next build writes it again. These are the values the google-services
     plugin would take from google-services.json. -->
<resources>
    <string name="google_app_id" translatable="false">${_xml(fcm.appId)}</string>
    <string name="google_api_key" translatable="false">${_xml(fcm.apiKey)}</string>
    <string name="gcm_defaultSenderId" translatable="false">${_xml(fcm.senderId)}</string>
    <string name="project_id" translatable="false">${_xml(fcm.projectId)}</string>
</resources>
''';

/// [value] as the text of an Android string resource: XML-escaped, and with
/// the two characters Android's own resource parser treats as escapes.
String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll("'", r"\'")
    .replaceAll('"', r'\"')
    .replaceAll('@', r'\@')
    .replaceAll('?', r'\?');

/// The Firebase service, as Java.
String dvAndroidPushServiceSource() => r'''
// GENERATED by dartvel build from dartvel.push.android. Do not edit: the next
// build writes it again.
//
// Firebase starts this service to deliver a message or a new token. It does
// nothing with either except hand them to DartvelPush, which keeps them until
// Dart asks.
package dev.dartvel.jni;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

public final class DartvelMessagingService extends FirebaseMessagingService {
  @Override
  public void onMessageReceived(RemoteMessage message) {
    DartvelPush.received(getApplicationContext(), message);
  }

  @Override
  public void onNewToken(String token) {
    DartvelPush.tokenRefreshed(getApplicationContext(), token);
  }
}
''';

/// The bridge, as Java.
String dvAndroidPushBridgeSource() => r'''
// GENERATED by dartvel build from dartvel.push.android. Do not edit: the next
// build writes it again.
//
// Firebase Cloud Messaging for PushNotifications, reached from Dart over JNI.
// Dart starts an operation and polls for its answer, and drains the messages
// that arrived. Every answer is a JSON object; a failure is {"error": "..."}
// rather than an exception thrown across JNI.
//
// Messages are kept in SharedPreferences, not memory: FCM starts the process
// to deliver a data message with no Flutter engine running, and a queue held
// only in memory is gone with that process before Dart ever looks.
//
// Nothing here logs: a token identifies a device and a payload is whatever
// the sender wrote, and neither belongs in logcat.
package dev.dartvel.jni;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;

import com.google.android.gms.tasks.OnCompleteListener;
import com.google.android.gms.tasks.Task;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.RemoteMessage;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

public final class DartvelPush {
  private DartvelPush() {}

  private static final String PREFERENCES = "dartvel_push";
  private static final String QUEUE = "queue";
  private static final String TOKEN = "token";
  private static final String SEEN = "seen_launch";
  private static final int MAX_QUEUED = 100;
  private static final int MAX_SEEN = 50;

  private static final Object lock = new Object();

  /// Answers waiting to be polled, by request id.
  private static final Map<String, String> answers = new ConcurrentHashMap<>();
  private static final AtomicLong nextId = new AtomicLong();

  private static SharedPreferences preferences(Context context) {
    return context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE);
  }

  private static String error(String message) {
    try {
      return new JSONObject().put("error", message).toString();
    } catch (JSONException impossible) {
      return "{\"error\":\"push failed\"}";
    }
  }

  /// Starts an operation and returns the id to poll for its answer.
  ///
  /// Operations: "token", "deleteToken", "subscribe" and "unsubscribe" (with
  /// "topic").
  public static String start(String request) {
    final String id = "p" + nextId.incrementAndGet();
    try {
      final JSONObject parsed = new JSONObject(request);
      final String operation = parsed.optString("op");
      final Context context = DartvelContext.context();
      if (context == null) {
        answers.put(id, error("there is no application Context yet"));
        return id;
      }
      final FirebaseMessaging messaging = FirebaseMessaging.getInstance();
      switch (operation) {
        case "token":
          messaging.getToken().addOnCompleteListener(
              new OnCompleteListener<String>() {
                @Override
                public void onComplete(Task<String> task) {
                  if (!task.isSuccessful() || task.getResult() == null) {
                    answers.put(id, error(describe(task.getException())));
                    return;
                  }
                  final String token = task.getResult();
                  preferences(context).edit().putString(TOKEN, token).apply();
                  try {
                    answers.put(id,
                        new JSONObject().put("token", token).toString());
                  } catch (JSONException impossible) {
                    answers.put(id, error("push failed"));
                  }
                }
              });
          break;
        case "deleteToken":
          messaging.deleteToken().addOnCompleteListener(
              new OnCompleteListener<Void>() {
                @Override
                public void onComplete(Task<Void> task) {
                  if (task.isSuccessful()) {
                    preferences(context).edit().remove(TOKEN).apply();
                    answers.put(id, "{\"ok\":true}");
                  } else {
                    answers.put(id, error(describe(task.getException())));
                  }
                }
              });
          break;
        case "subscribe":
        case "unsubscribe":
          final String topic = parsed.optString("topic");
          if (topic.isEmpty()) {
            answers.put(id, error("a topic is required"));
            break;
          }
          final Task<Void> change = operation.equals("subscribe")
              ? messaging.subscribeToTopic(topic)
              : messaging.unsubscribeFromTopic(topic);
          change.addOnCompleteListener(new OnCompleteListener<Void>() {
            @Override
            public void onComplete(Task<Void> task) {
              answers.put(id, task.isSuccessful()
                  ? "{\"ok\":true}"
                  : error(describe(task.getException())));
            }
          });
          break;
        default:
          answers.put(id, error("unknown push operation"));
      }
    } catch (Throwable failure) {
      // Firebase throws IllegalStateException when it was never initialised,
      // which is what a missing or wrong dartvel.push.android.fcm looks like.
      answers.put(id, error(describe(failure)));
    }
    return id;
  }

  private static String describe(Throwable failure) {
    if (failure == null) return "push failed";
    final String message = failure.getMessage();
    return failure.getClass().getSimpleName()
        + (message == null ? "" : ": " + message);
  }

  /// The answer for [id], or null while the operation is still running.
  public static String poll(String id) {
    return answers.remove(id);
  }

  /// Everything that arrived since the last call, as a JSON array, oldest
  /// first: messages Firebase delivered, and the notification the person
  /// tapped to open the application.
  public static String drainMessages() {
    final Context context = DartvelContext.context();
    final JSONArray out = new JSONArray();
    if (context == null) return out.toString();
    synchronized (lock) {
      final SharedPreferences preferences = preferences(context);
      try {
        final JSONArray queued = new JSONArray(preferences.getString(QUEUE, "[]"));
        for (int i = 0; i < queued.length(); i++) out.put(queued.get(i));
      } catch (JSONException cutShort) {
        // A queue cut short by the process dying mid-write is dropped
        // rather than blocking every later message.
      }
      preferences.edit().remove(QUEUE).apply();
      final JSONObject launched = launchEntry(preferences);
      if (launched != null) out.put(launched);
    }
    return out.toString();
  }

  /// Called by the Firebase service.
  static void received(Context context, RemoteMessage message) {
    try {
      final JSONObject entry = new JSONObject();
      final String id = message.getMessageId() != null
          ? message.getMessageId()
          : UUID.randomUUID().toString();
      final RemoteMessage.Notification notification = message.getNotification();
      final JSONObject data = new JSONObject();
      for (Map.Entry<String, String> field : message.getData().entrySet()) {
        data.put(field.getKey(), field.getValue());
      }
      entry.put("id", id);
      entry.put("title", notification == null ? JSONObject.NULL : notification.getTitle());
      entry.put("body", notification == null ? JSONObject.NULL : notification.getBody());
      entry.put("data", data);
      entry.put("receivedAt", message.getSentTime() > 0
          ? message.getSentTime()
          : System.currentTimeMillis());
      entry.put("opened", false);
      enqueue(context, entry);
    } catch (JSONException impossible) {
      // Every key above is a literal; JSONObject.put throws only on a
      // non-finite number or a null key.
    }
  }

  /// Called by the Firebase service when the registration token changes.
  static void tokenRefreshed(Context context, String token) {
    preferences(context).edit().putString(TOKEN, token).apply();
  }

  private static void enqueue(Context context, JSONObject entry) {
    synchronized (lock) {
      final SharedPreferences preferences = preferences(context);
      JSONArray queue;
      try {
        queue = new JSONArray(preferences.getString(QUEUE, "[]"));
      } catch (JSONException cutShort) {
        queue = new JSONArray();
      }
      final JSONArray kept = new JSONArray();
      final int skip = Math.max(0, queue.length() + 1 - MAX_QUEUED);
      for (int i = skip; i < queue.length(); i++) {
        try {
          kept.put(queue.get(i));
        } catch (JSONException unreadable) {
          // Skipped.
        }
      }
      kept.put(entry);
      preferences.edit().putString(QUEUE, kept.toString()).commit();
    }
  }

  /// The notification the person tapped to open the application, from the
  /// launch Intent. FCM puts the message id and the data fields in its
  /// extras. Reported once per message: a task restored from recents can
  /// carry the same Intent again.
  private static JSONObject launchEntry(SharedPreferences preferences) {
    final Activity activity = DartvelContext.activity();
    if (activity == null) return null;
    final Intent intent = activity.getIntent();
    if (intent == null) return null;
    final Bundle extras = intent.getExtras();
    if (extras == null) return null;
    final String id = extras.getString("google.message_id");
    if (id == null) return null;

    JSONArray seen;
    try {
      seen = new JSONArray(preferences.getString(SEEN, "[]"));
    } catch (JSONException cutShort) {
      seen = new JSONArray();
    }
    for (int i = 0; i < seen.length(); i++) {
      if (id.equals(seen.optString(i))) return null;
    }
    final JSONArray remembered = new JSONArray();
    for (int i = Math.max(0, seen.length() + 1 - MAX_SEEN); i < seen.length(); i++) {
      remembered.put(seen.optString(i));
    }
    remembered.put(id);
    preferences.edit().putString(SEEN, remembered.toString()).apply();

    try {
      final JSONObject data = new JSONObject();
      for (String key : extras.keySet()) {
        if (key.startsWith("google.") || key.startsWith("gcm.")
            || key.equals("from") || key.equals("collapse_key")) {
          continue;
        }
        final Object value = extras.get(key);
        if (value instanceof String) data.put(key, value);
      }
      final JSONObject entry = new JSONObject();
      entry.put("id", id);
      entry.put("title", JSONObject.NULL);
      entry.put("body", JSONObject.NULL);
      entry.put("data", data);
      entry.put("receivedAt", System.currentTimeMillis());
      entry.put("opened", true);
      return entry;
    } catch (JSONException impossible) {
      return null;
    }
  }
}
''';
