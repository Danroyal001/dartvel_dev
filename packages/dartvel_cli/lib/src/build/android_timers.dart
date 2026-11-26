/// `dartvel.timers` on Android: the broadcast receiver that rings a DV.Timers
/// timer from the operating system, with the app closed and the screen off.
///
/// A Dart timer stops with the process, and Android stops the process of an
/// app in the background whenever it likes, so the ringing has to be the
/// system's: an alarm-clock alarm (`AlarmManager.setAlarmClock`, which Doze
/// lets through on time), a notification on an alarm-sound channel, and its
/// snooze and dismiss buttons handled by the same receiver. The Dart side
/// sends the receiver SCHEDULE and CANCEL broadcasts; what the receiver did
/// while the app was away it writes to [dvAndroidTimerEventsFile], which the
/// Dart side reads back.
///
/// Written beside MainActivity in the app's own package, as the badge service
/// is, and declared in the manifest between markers so turning the setting off
/// takes back exactly what was added.
library dartvel_cli.build.android_timers;

/// The broadcast the Dart side sends to have a timer rung at a time.
const String dvAndroidTimerSchedule = 'dev.dartvel.timer.SCHEDULE';

/// The broadcast that forgets a timer's alarm and takes its notification away.
const String dvAndroidTimerCancel = 'dev.dartvel.timer.CANCEL';

/// The broadcast that takes a timer's notification away and keeps its alarm.
const String dvAndroidTimerSilence = 'dev.dartvel.timer.SILENCE';

/// Under the app's files directory: one line per action taken in a
/// notification, `<id>\t<action>\t<epoch ms>`.
const String dvAndroidTimerEventsFile = 'dartvel-timers/events.txt';

/// Whether `dartvel.timers` is true. Anything else is off, so a typo cannot
/// add permissions to an app.
bool dvTimersEnabled(Map<Object?, Object?> dartvel) => dartvel['timers'] == true;

const String _permissionsStart = '    <!-- dartvel.timers: begin -->';
const String _permissionsEnd = '    <!-- dartvel.timers: end -->';
const String _receiversStart = '        <!-- dartvel.timers receivers: begin -->';
const String _receiversEnd = '        <!-- dartvel.timers receivers: end -->';

const List<String> _permissions = <String>[
  'android.permission.POST_NOTIFICATIONS',
  // Exact alarms: asked of the person from Android 14; without it a timer
  // still rings, a little late when the phone is dozing.
  'android.permission.SCHEDULE_EXACT_ALARM',
  'android.permission.RECEIVE_BOOT_COMPLETED',
  'android.permission.VIBRATE',
];

/// [manifest] with the receivers and permissions when [enabled], and with
/// exactly what an earlier write added taken out when not.
String dvAndroidTimerManifest(String manifest, {required bool enabled}) {
  String out = _strip(manifest, _permissionsStart, _permissionsEnd);
  out = _strip(out, _receiversStart, _receiversEnd);
  if (!enabled) return out;
  final List<String> missing = <String>[
    for (final String permission in _permissions)
      if (!out.contains('"$permission"')) permission,
  ];
  final int application = out.indexOf('    <application');
  if (application >= 0 && missing.isNotEmpty) {
    final String block = '$_permissionsStart\n'
        '${missing.map((String permission) => '    <uses-permission android:name="$permission"/>\n').join()}'
        '$_permissionsEnd\n';
    out = out.replaceRange(application, application, block);
  }
  final int close = out.lastIndexOf('    </application>');
  if (close >= 0) {
    const String receivers = '$_receiversStart\n'
        '        <receiver android:name=".DartvelTimerReceiver" android:exported="false"/>\n'
        '        <receiver android:name=".DartvelTimerBootReceiver" android:exported="true">\n'
        '            <intent-filter>\n'
        '                <action android:name="android.intent.action.BOOT_COMPLETED"/>\n'
        '                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>\n'
        '            </intent-filter>\n'
        '        </receiver>\n'
        '$_receiversEnd\n';
    out = out.replaceRange(close, close, receivers);
  }
  return out;
}

String _strip(String text, String start, String end) {
  final int from = text.indexOf(start);
  if (from < 0) return text;
  final int to = text.indexOf(end, from);
  if (to < 0) return text;
  return text.replaceRange(from, to + end.length + 1, '');
}

/// DartvelTimerReceiver.kt, in the app's [package], beside its MainActivity.
String dvAndroidTimerReceiverSource(String package) => 'package $package\n$_receiverBody'
    .replaceAll('__SCHEDULE__', dvAndroidTimerSchedule)
    .replaceAll('__CANCEL__', dvAndroidTimerCancel)
    .replaceAll('__SILENCE__', dvAndroidTimerSilence)
    .replaceAll('__EVENTS__', dvAndroidTimerEventsFile);

const String _receiverBody = r'''

// Written by dartvel build (dartvel.timers). Edits are replaced.
//
// DV.Timers on Android: rings a timer from the operating system, so it rings
// with the app closed and the screen off, and handles the notification's
// snooze and dismiss buttons. The app sends SCHEDULE and CANCEL; what was
// done here while the app was away goes to files/__EVENTS__.

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.RingtoneManager
import android.os.Build
import java.io.File

private const val SCHEDULE = "__SCHEDULE__"
private const val CANCEL = "__CANCEL__"
private const val SILENCE = "__SILENCE__"
private const val FIRE = "dev.dartvel.timer.FIRE"
private const val SNOOZE = "dev.dartvel.timer.SNOOZE"
private const val DISMISS = "dev.dartvel.timer.DISMISS"
private const val EVENTS = "__EVENTS__"
private const val CHANNEL = "dartvel_timers"
private const val PREFS = "dartvel_timers"
private const val NOTIFICATION = 7041
private const val SEPARATOR = "\u0000"

class DartvelTimerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("id") ?: return
        when (intent.action) {
            SCHEDULE -> DartvelTimers.schedule(
                context,
                id,
                intent.getStringExtra("title") ?: "",
                intent.getStringExtra("body") ?: "",
                intent.getLongExtra("at", 0L),
                intent.getStringExtra("route") ?: "",
            )
            CANCEL -> DartvelTimers.cancel(context, id)
            SILENCE -> DartvelTimers.manager(context).cancel(id, NOTIFICATION)
            FIRE -> DartvelTimers.fire(context, id)
            SNOOZE -> {
                val minutes = intent.getIntExtra("minutes", 1)
                DartvelTimers.snooze(context, id, minutes)
                DartvelTimers.record(context, id, "snooze-$minutes")
            }
            DISMISS -> {
                DartvelTimers.cancel(context, id)
                DartvelTimers.record(context, id, "dismiss")
            }
        }
    }
}

/// Alarms do not survive a restart of the phone or an update of the app; this
/// puts back every timer still waiting. It is reachable from outside the app,
/// so it does nothing but re-arm what the app itself asked for.
class DartvelTimerBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        for ((id, value) in prefs.all) {
            val kept = (value as? String)?.split(SEPARATOR) ?: continue
            if (kept.size < 4) continue
            val at = kept[0].toLongOrNull() ?: continue
            // Long past: it rang, or the phone was off through it and a late
            // ring would only confuse.
            if (at < System.currentTimeMillis() - 10 * 60_000L) continue
            DartvelTimers.schedule(context, id, kept[1], kept[2], at, kept[3])
        }
    }
}

internal object DartvelTimers {
    fun manager(context: Context): NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun alarms(context: Context): AlarmManager =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    private fun pending(context: Context, action: String, id: String, minutes: Int): PendingIntent {
        val intent = Intent(context, DartvelTimerReceiver::class.java)
            .setAction(action)
            .putExtra("id", id)
            .putExtra("minutes", minutes)
        return PendingIntent.getBroadcast(
            context,
            "$action/$id/$minutes".hashCode(),
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    fun schedule(context: Context, id: String, title: String, body: String, at: Long, route: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(id, listOf(at.toString(), title, body, route).joinToString(SEPARATOR))
            .apply()
        val alarmManager = alarms(context)
        val fire = pending(context, FIRE, id, 0)
        if (Build.VERSION.SDK_INT < 31 || alarmManager.canScheduleExactAlarms()) {
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val show = launch?.let {
                PendingIntent.getActivity(context, id.hashCode(), it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            }
            alarmManager.setAlarmClock(AlarmManager.AlarmClockInfo(at, show), fire)
        } else {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, fire)
        }
    }

    fun cancel(context: Context, id: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(id).apply()
        alarms(context).cancel(pending(context, FIRE, id, 0))
        manager(context).cancel(id, NOTIFICATION)
    }

    fun snooze(context: Context, id: String, minutes: Int) {
        val kept = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(id, null)?.split(SEPARATOR) ?: return
        if (kept.size < 4) return
        manager(context).cancel(id, NOTIFICATION)
        schedule(context, id, kept[1], kept[2], System.currentTimeMillis() + minutes * 60_000L, kept[3])
    }

    fun record(context: Context, id: String, action: String) {
        val file = File(context.filesDir, EVENTS)
        file.parentFile?.mkdirs()
        file.appendText("$id\t$action\t${System.currentTimeMillis()}\n")
    }

    @Suppress("DEPRECATION")
    fun fire(context: Context, id: String) {
        val kept = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(id, null)?.split(SEPARATOR) ?: return
        if (kept.size < 4) return
        val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(CHANNEL, "Timers", NotificationManager.IMPORTANCE_HIGH)
            channel.description = "A timer you set has finished"
            channel.setSound(
                sound,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            channel.enableVibration(true)
            channel.vibrationPattern = longArrayOf(0, 400, 200, 400, 200, 800)
            manager(context).createNotificationChannel(channel)
            Notification.Builder(context, CHANNEL)
        } else {
            Notification.Builder(context)
                .setSound(sound, AudioManager.STREAM_ALARM)
                .setPriority(Notification.PRIORITY_MAX)
                .setVibrate(longArrayOf(0, 400, 200, 400, 200, 800))
        }
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        if (launch != null) {
            builder.setContentIntent(
                PendingIntent.getActivity(context, id.hashCode(), launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
            )
        }
        builder
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(kept[1])
            .setContentText(kept[2])
            .setCategory(Notification.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setDeleteIntent(pending(context, DISMISS, id, 0))
            .addAction(0, "+1 min", pending(context, SNOOZE, id, 1))
            .addAction(0, "+5 min", pending(context, SNOOZE, id, 5))
            .addAction(0, "Dismiss", pending(context, DISMISS, id, 0))
        val notification = builder.build()
        // Repeats the sound until it is answered, as a kitchen timer does.
        notification.flags = notification.flags or Notification.FLAG_INSISTENT
        manager(context).notify(id, NOTIFICATION, notification)
    }
}
''';
