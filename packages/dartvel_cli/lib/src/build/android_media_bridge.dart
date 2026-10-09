/// The Android half of `DVBox.video`, `DVBox.audio` and `DVBox.camera`:
/// Media3 ExoPlayer, a Media3 session and its foreground service, and
/// CameraX, as Java the build writes into the application.
///
/// Java for the reason the capture bridge is Java: the work is listeners,
/// futures, a Looper and an executor, and each of those is a jnigen binding
/// that has to exist and be right before Dart could express it, where `javac`
/// checks the Java at build time. The Dart side calls a handful of static
/// methods over JNI and polls a queue of JSON events; nothing calls back into
/// Dart and nothing is a platform channel.
///
/// Written only for an application whose code uses them. Placement follows
/// call sites: a torch application does not ship a video player because the
/// framework has one, and the Gradle dependencies and manifest lines come and
/// go with the classes.
library dartvel_cli.build.android_media_bridge;

import 'package:dartvel_core/dartvel.dart'
    show
        dvAndroidAudioFocusClass,
        dvAndroidCameraClass,
        dvAndroidMediaPlayerClass,
        dvAndroidMediaSessionClass;

/// Media3's version, pinned rather than floating: the session API moved
/// between minor versions and a build that resolved a different one tomorrow
/// is a regression nobody changed anything to cause.
const String dvAndroidMedia3Version = '1.11.1';

/// CameraX's version, for the same reason.
const String dvAndroidCameraXVersion = '1.5.1';

const String _dir = 'android/app/src/main/java/dev/dartvel/jni';

String _path(String jniClass) => '$_dir/${jniClass.split('/').last}.java';

final String dvAndroidMediaPlayerPath = _path(dvAndroidMediaPlayerClass);
final String dvAndroidMediaSessionPath = _path(dvAndroidMediaSessionClass);
final String dvAndroidAudioFocusPath = _path(dvAndroidAudioFocusClass);
final String dvAndroidCameraPath = _path(dvAndroidCameraClass);
const String dvAndroidMediaServicePath = '$_dir/DartvelMediaService.java';

/// What an application's code uses.
final class DVAndroidMediaUsage {
  const DVAndroidMediaUsage({this.player = false, this.camera = false});

  final bool player;
  final bool camera;

  bool get any => player || camera;

  @override
  String toString() => 'DVAndroidMediaUsage(player: $player, camera: $camera)';
}

final RegExp _comment = RegExp(r'//[^\n]*|/\*[\s\S]*?\*/');
final RegExp _playerCall = RegExp(
    r'\bDVBox\s*\.\s*(?:video|audio)\s*\(|\bDVBackgroundVideo\s*\(|'
    r'\.\s*backgroundVideo\s*\(|\.\s*precache\s*\(');
final RegExp _cameraCall =
    RegExp(r'\bDVBox\s*\.\s*camera\s*\(|\.\s*recordVideo\s*\(');

/// What [sources] -- the Dart files under `lib/` -- use. Comments do not
/// count: a doc comment mentioning `DVBox.video` is not a player.
DVAndroidMediaUsage dvAndroidMediaUsage(Iterable<String> sources) {
  bool player = false;
  bool camera = false;
  for (final String source in sources) {
    final String code = source.replaceAll(_comment, '');
    player = player || _playerCall.hasMatch(code);
    camera = camera || _cameraCall.hasMatch(code);
    if (player && camera) break;
  }
  return DVAndroidMediaUsage(player: player, camera: camera);
}

/// The `dartvel.android.permissions` names [usage] needs on top of what the
/// project declared. The camera box records video with sound, so it needs
/// both; a player needs none.
List<String> dvAndroidMediaPermissions(DVAndroidMediaUsage usage) =>
    usage.camera ? const <String>['camera', 'microphone'] : const <String>[];

/// The static methods the Dart side calls, as Java declares them. A test
/// checks every one is in the generated source, because a renamed method is
/// a NoSuchMethodError on the device and nowhere else.
const List<String> dvAndroidMediaJavaMethods = <String>[
  'long create(long engineId, boolean video)',
  'void open(long handle, String uri)',
  'void play(long handle)',
  'void pause(long handle)',
  'void seek(long handle, long positionMs, long generation)',
  'void setVolume(long handle, double volume)',
  'long textureId(long handle)',
  'String poll(long handle)',
  'boolean enterPictureInPicture(long handle)',
  'boolean backgroundDeclared()',
  'void dispose(long handle)',
  'void publish(String title, String artist, String album, String artwork, '
      'boolean playing, long positionMs, long durationMs)',
  'void clear()',
  'String commands()',
  'boolean request()',
  'void abandon()',
  'long losses()',
  'String capabilities()',
  'long createCamera(long engineId)',
  'void openCamera(long handle, String lens)',
  'void closeCamera(long handle)',
  'void takePhoto(long handle, String path, String flash)',
  'void startRecording(long handle, String path, String quality, '
      'boolean audio)',
  'void stopRecording(long handle)',
  'void setTorch(long handle, boolean on)',
  'long cameraTextureId(long handle)',
  'String pollCamera(long handle)',
  'void disposeCamera(long handle)',
];

/// The Java [usage] needs, by path. Empty when it needs none.
Map<String, String> dvAndroidMediaSources(DVAndroidMediaUsage usage) =>
    <String, String>{
      if (usage.player) ...<String, String>{
        dvAndroidMediaPlayerPath: _playerSource,
        dvAndroidMediaSessionPath: _sessionSource,
        dvAndroidMediaServicePath: _serviceSource,
        dvAndroidAudioFocusPath: _focusSource,
      },
      if (usage.camera) dvAndroidCameraPath: _cameraSource,
    };

/// Every path [dvAndroidMediaSources] can write, for removing what a build
/// that no longer uses media left behind.
List<String> get dvAndroidMediaAllPaths => <String>[
      dvAndroidMediaPlayerPath,
      dvAndroidMediaSessionPath,
      dvAndroidMediaServicePath,
      dvAndroidAudioFocusPath,
      dvAndroidCameraPath,
    ];

// --- Gradle -----------------------------------------------------------------

const String _gradleStart = '// dartvel.media: start';
const String _gradleEnd = '// dartvel.media: end';

String _stripBlock(String text, String start, String end) {
  final int from = text.indexOf(start);
  if (from < 0) return text;
  final int to = text.indexOf(end, from);
  if (to < 0) return text;
  // The whole lines, and the blank line written before the block.
  int lineStart = text.lastIndexOf('\n', from) + 1;
  int lineEnd = text.indexOf('\n', to);
  lineEnd = lineEnd < 0 ? text.length : lineEnd + 1;
  if (lineStart >= 1 && text.substring(0, lineStart).endsWith('\n\n')) {
    lineStart -= 1;
  }
  return text.substring(0, lineStart) + text.substring(lineEnd);
}

/// [gradle] -- `android/app/build.gradle.kts`, or the Groovy `build.gradle`
/// when [kotlin] is false -- with the libraries [usage] needs, in a marked
/// `dependencies` block of its own that a later build replaces or removes.
String dvAndroidMediaGradle(String gradle, DVAndroidMediaUsage usage,
    {required bool kotlin}) {
  final String stripped = _stripBlock(gradle, _gradleStart, _gradleEnd);
  if (!usage.any) return stripped;
  final List<String> libraries = <String>[
    if (usage.player) ...<String>[
      'androidx.media3:media3-exoplayer:$dvAndroidMedia3Version',
      'androidx.media3:media3-session:$dvAndroidMedia3Version',
    ],
    if (usage.camera) ...<String>[
      'androidx.camera:camera-camera2:$dvAndroidCameraXVersion',
      'androidx.camera:camera-lifecycle:$dvAndroidCameraXVersion',
      'androidx.camera:camera-video:$dvAndroidCameraXVersion',
    ],
  ];
  final StringBuffer out = StringBuffer(stripped.endsWith('\n') ? stripped : '$stripped\n')
    ..writeln()
    ..writeln(_gradleStart)
    ..writeln('// What DVBox.video, DVBox.audio and DVBox.camera use. Written by')
    ..writeln('// dartvel build from the code under lib/; do not edit.')
    ..writeln('dependencies {');
  for (final String library in libraries) {
    out.writeln(kotlin
        ? '    implementation("$library")'
        : "    implementation '$library'");
  }
  out
    ..writeln('}')
    ..writeln(_gradleEnd);
  return out.toString();
}

// --- manifest ---------------------------------------------------------------

const String _permStart = '    <!-- dartvel.media: start -->\n';
const String _permEnd = '    <!-- dartvel.media: end -->\n';
const String _appStart = '        <!-- dartvel.media.app: start -->\n';
const String _appEnd = '        <!-- dartvel.media.app: end -->\n';
const String _pip = '\n            android:supportsPictureInPicture="true"';

String _removeBlock(String text, String start, String end) {
  final int from = text.indexOf(start);
  if (from < 0) return text;
  final int to = text.indexOf(end, from);
  if (to < 0) return text;
  return text.substring(0, from) + text.substring(to + end.length);
}

/// [manifest] with what [usage] needs: INTERNET for a URL, the foreground
/// service a session keeps playing in the background through, and
/// picture-in-picture on the main activity. Marked, so a second build
/// rewrites rather than duplicates, and an application that stops using
/// media gets its manifest back as it was.
String dvAndroidMediaManifest(String manifest, DVAndroidMediaUsage usage) {
  String out = _removeBlock(manifest, _permStart, _permEnd);
  out = _removeBlock(out, _appStart, _appEnd);
  out = out.replaceFirst(_pip, '');
  if (!usage.player) return out;

  final List<String> permissions = <String>[
    // Flutter's template declares it in debug and profile only, so a player
    // that streams worked in every build anyone tried and failed in release.
    if (!out.contains('"android.permission.INTERNET"'))
      'android.permission.INTERNET',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
    'android.permission.WAKE_LOCK',
  ].where((String name) => !out.contains('"$name"')).toList();

  final int application = out.indexOf('<application');
  if (application < 0) return out;
  final int lineStart = out.lastIndexOf('\n', application) + 1;
  final StringBuffer perms = StringBuffer()..write(_permStart);
  for (final String name in permissions) {
    perms.writeln('    <uses-permission android:name="$name"/>');
  }
  perms.write(_permEnd);
  out = out.substring(0, lineStart) + perms.toString() + out.substring(lineStart);

  final int close = out.indexOf('</application>');
  if (close < 0) return out;
  final int closeLine = out.lastIndexOf('\n', close) + 1;
  final String service = StringBuffer()
      .let((StringBuffer b) => b
        ..write(_appStart)
        ..writeln('        <!-- Keeps a DVMediaSession playing with the application in')
        ..writeln('             the background, and puts its controls on the lock')
        ..writeln('             screen. -->')
        ..writeln('        <service')
        ..writeln('            android:name="dev.dartvel.jni.DartvelMediaService"')
        ..writeln('            android:foregroundServiceType="mediaPlayback"')
        ..writeln('            android:exported="true">')
        ..writeln('            <intent-filter>')
        ..writeln('                <action android:name="androidx.media3.session.MediaSessionService"/>')
        ..writeln('            </intent-filter>')
        ..writeln('        </service>')
        ..write(_appEnd))
      .toString();
  out = out.substring(0, closeLine) + service + out.substring(closeLine);

  // Picture-in-picture is an attribute of the activity that goes small,
  // which in a Flutter application is the one the engine draws into.
  final RegExpMatch? main =
      RegExp(r'<activity\s+android:name="\.MainActivity"').firstMatch(out);
  if (main != null && !out.contains('android:supportsPictureInPicture')) {
    out = out.substring(0, main.end) + _pip + out.substring(main.end);
  }
  return out;
}

extension on StringBuffer {
  StringBuffer let(StringBuffer Function(StringBuffer) build) => build(this);
}

// --- Java -------------------------------------------------------------------

const String _header = '''
// GENERATED by dartvel build because the code under lib/ uses Dartvel's
// media. Do not edit: the next build writes it again, and a build of an
// application that no longer uses media deletes it.
''';

const String _json = r'''
  static String quote(String value) {
    if (value == null) return "null";
    StringBuilder out = new StringBuilder("\"");
    for (int i = 0; i < value.length(); i++) {
      char c = value.charAt(i);
      switch (c) {
        case '"': out.append("\\\""); break;
        case '\\': out.append("\\\\"); break;
        case '\n': out.append("\\n"); break;
        case '\r': out.append("\\r"); break;
        case '\t': out.append("\\t"); break;
        default:
          if (c < 0x20) {
            out.append(String.format("\\u%04x", (int) c));
          } else {
            out.append(c);
          }
      }
    }
    return out.append('"').toString();
  }

  static String drain(java.util.List<String> events) {
    if (events.isEmpty()) return null;
    StringBuilder out = new StringBuilder("[");
    for (int i = 0; i < events.size(); i++) {
      if (i > 0) out.append(',');
      out.append(events.get(i));
    }
    events.clear();
    return out.append(']').toString();
  }

  /// Runs [work] on the main thread and waits for it. Flutter runs Dart on
  /// the main thread on current Android, so this is usually a direct call;
  /// the hand-off is for an engine configured otherwise, because ExoPlayer
  /// and CameraX throw when touched from any other thread.
  static <T> T onMain(java.util.concurrent.Callable<T> work) {
    if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) {
      try {
        return work.call();
      } catch (RuntimeException error) {
        throw error;
      } catch (Exception error) {
        throw new RuntimeException(error);
      }
    }
    java.util.concurrent.FutureTask<T> task =
        new java.util.concurrent.FutureTask<>(work);
    new android.os.Handler(android.os.Looper.getMainLooper()).post(task);
    try {
      return task.get(5, java.util.concurrent.TimeUnit.SECONDS);
    } catch (Exception error) {
      throw new RuntimeException(error);
    }
  }
''';

final String _playerSource = '''
package dev.dartvel.jni;

$_header
import android.app.Activity;
import android.app.PictureInPictureParams;
import android.content.ComponentName;
import android.content.Context;
import android.os.Build;
import android.util.Rational;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.VideoSize;
import androidx.media3.exoplayer.ExoPlayer;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.view.TextureRegistry;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/// One ExoPlayer per handle. Everything here runs on the main thread.
public final class DartvelMediaPlayer {
  private static final Map<Long, DartvelMediaPlayer> PLAYERS = new HashMap<>();
  private static long sNext = 1;
  private static DartvelMediaPlayer sLastStarted;

  final ExoPlayer player;
  private final TextureRegistry.SurfaceProducer producer;
  private final List<String> events = new ArrayList<>();
  private boolean ready = false;
  private long pendingSeek = 0;
  private long completedSeek = 0;
  private long lastBuffered = -1;
  private int width = 0;
  private int height = 0;
  private Activity pipActivity;
  private boolean pip = false;

  private DartvelMediaPlayer(Context context,
      TextureRegistry.SurfaceProducer producer) {
    this.producer = producer;
    player = new ExoPlayer.Builder(context).build();
    // Focus is DVAudioFocus's, through DartvelAudioFocus: one arbiter, not
    // two that each think they own it.
    player.setAudioAttributes(new AudioAttributes.Builder()
        .setUsage(C.USAGE_MEDIA)
        .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
        .build(), false);
    // Headphones pulled out pause rather than play to the room.
    player.setHandleAudioBecomingNoisy(true);
    if (producer != null) {
      producer.setCallback(new TextureRegistry.SurfaceProducer.Callback() {
        @Override
        public void onSurfaceAvailable() {
          player.setVideoSurface(producer.getSurface());
        }

        @Override
        public void onSurfaceCleanup() {
          player.setVideoSurface(null);
        }
      });
      player.setVideoSurface(producer.getSurface());
    }
    player.addListener(new Player.Listener() {
      @Override
      public void onPlaybackStateChanged(int state) {
        if (state == Player.STATE_BUFFERING) {
          add("{\\"type\\":\\"buffering\\"}");
        } else if (state == Player.STATE_READY) {
          if (!ready) {
            ready = true;
            long duration = player.getDuration();
            add("{\\"type\\":\\"ready\\",\\"durationMs\\":"
                + (duration == C.TIME_UNSET ? 0 : duration) + "}");
          } else if (!player.isPlaying()) {
            add("{\\"type\\":\\"paused\\"}");
          }
        } else if (state == Player.STATE_ENDED) {
          add("{\\"type\\":\\"completed\\"}");
        }
      }

      @Override
      public void onIsPlayingChanged(boolean playing) {
        if (playing) {
          add("{\\"type\\":\\"playing\\"}");
        } else if (player.getPlaybackState() == Player.STATE_READY) {
          add("{\\"type\\":\\"paused\\"}");
        }
      }

      @Override
      public void onPlayerError(PlaybackException error) {
        add("{\\"type\\":\\"failed\\",\\"message\\":"
            + quote(error.getErrorCodeName() + ": " + error.getMessage()) + "}");
      }

      @Override
      public void onVideoSizeChanged(VideoSize size) {
        if (size.width == 0 || size.height == 0) return;
        width = size.width;
        height = size.height;
        if (producer != null) producer.setSize(size.width, size.height);
        add("{\\"type\\":\\"videoSize\\",\\"width\\":" + size.width + ",\\"height\\":"
            + size.height + "}");
      }

      @Override
      public void onPositionDiscontinuity(Player.PositionInfo oldPosition,
          Player.PositionInfo newPosition, int reason) {
        if (reason != Player.DISCONTINUITY_REASON_SEEK) return;
        completedSeek = pendingSeek;
        add("{\\"type\\":\\"seekCompleted\\",\\"gen\\":" + completedSeek
            + ",\\"ms\\":" + newPosition.positionMs + "}");
      }
    });
  }

  private void add(String event) {
    events.add(event);
  }

  private static DartvelMediaPlayer get(long handle) {
    return PLAYERS.get(handle);
  }

  /// The player that last started, which is the one the media session and
  /// the lock screen follow.
  static ExoPlayer lastStarted() {
    DartvelMediaPlayer last = sLastStarted;
    return last == null ? null : last.player;
  }

  public static long create(long engineId, boolean video) {
    return onMain(() -> {
      Context context = DartvelContext.context();
      if (context == null) return 0L;
      TextureRegistry.SurfaceProducer producer = null;
      if (video) {
        FlutterEngine engine = FlutterEngine.engineForId(engineId);
        if (engine != null) {
          producer = engine.getRenderer().createSurfaceProducer();
        }
      }
      long handle = sNext++;
      PLAYERS.put(handle, new DartvelMediaPlayer(context, producer));
      return handle;
    });
  }

  public static void open(long handle, String uri) {
    onMain(() -> {
      DartvelMediaPlayer p = get(handle);
      if (p != null) {
        p.player.setMediaItem(MediaItem.fromUri(uri));
        p.player.prepare();
      }
      return null;
    });
  }

  public static void play(long handle) {
    onMain(() -> {
      DartvelMediaPlayer p = get(handle);
      if (p != null) {
        sLastStarted = p;
        p.player.play();
        DartvelMediaSession.follow(p.player);
      }
      return null;
    });
  }

  public static void pause(long handle) {
    onMain(() -> {
      DartvelMediaPlayer p = get(handle);
      if (p != null) p.player.pause();
      return null;
    });
  }

  public static void seek(long handle, long positionMs, long generation) {
    onMain(() -> {
      DartvelMediaPlayer p = get(handle);
      if (p != null) {
        p.pendingSeek = generation;
        p.player.seekTo(positionMs);
      }
      return null;
    });
  }

  public static void setVolume(long handle, double volume) {
    onMain(() -> {
      DartvelMediaPlayer p = get(handle);
      if (p != null) p.player.setVolume((float) volume);
      return null;
    });
  }

  public static long textureId(long handle) {
    return onMain(() -> {
      DartvelMediaPlayer p = get(handle);
      return p == null || p.producer == null ? -1L : p.producer.id();
    });
  }

  /// What happened since the last poll, as a JSON array, or null for
  /// nothing. The position is measured here, so a Dart timer polling is
  /// what moves the scrubber.
  public static String poll(long handle) {
    return onMain(() -> {
      DartvelMediaPlayer p = get(handle);
      if (p == null) return null;
      if (p.player.isPlaying()) {
        p.add("{\\"type\\":\\"position\\",\\"ms\\":" + p.player.getCurrentPosition()
            + ",\\"seek\\":" + p.completedSeek + "}");
      }
      long buffered = p.player.getBufferedPosition();
      if (buffered != p.lastBuffered && p.ready) {
        p.lastBuffered = buffered;
        p.add("{\\"type\\":\\"buffered\\",\\"ms\\":" + buffered + "}");
      }
      Activity activity = p.pipActivity;
      boolean inPip = activity != null && Build.VERSION.SDK_INT >= 24
          && activity.isInPictureInPictureMode();
      if (inPip != p.pip) {
        p.pip = inPip;
        p.add("{\\"type\\":\\"pip\\",\\"active\\":" + inPip + "}");
      }
      return drain(p.events);
    });
  }

  /// Floats the activity, which is the application's whole window: on
  /// Android picture-in-picture is the activity going small, not one view.
  public static boolean enterPictureInPicture(long handle) {
    return onMain(() -> {
      DartvelMediaPlayer p = get(handle);
      Activity activity = DartvelContext.activity();
      if (p == null || activity == null || Build.VERSION.SDK_INT < 26) {
        return false;
      }
      PictureInPictureParams.Builder params = new PictureInPictureParams.Builder();
      if (p.width > 0 && p.height > 0) {
        // Android refuses ratios outside 1:2.39 to 2.39:1.
        double ratio = (double) p.width / p.height;
        if (ratio > 2.39) {
          params.setAspectRatio(new Rational(239, 100));
        } else if (ratio < 1 / 2.39) {
          params.setAspectRatio(new Rational(100, 239));
        } else {
          params.setAspectRatio(new Rational(p.width, p.height));
        }
      }
      try {
        p.pipActivity = activity;
        return activity.enterPictureInPictureMode(params.build());
      } catch (IllegalStateException error) {
        // The manifest does not declare supportsPictureInPicture, or the
        // person turned it off for this application in Settings.
        return false;
      }
    });
  }

  /// Whether the service a session keeps playing through is in this
  /// application's manifest, as Android reads it.
  public static boolean backgroundDeclared() {
    Context context = DartvelContext.context();
    if (context == null) return false;
    try {
      context.getPackageManager().getServiceInfo(
          new ComponentName(context, DartvelMediaService.class), 0);
      return true;
    } catch (Exception error) {
      return false;
    }
  }

  public static void dispose(long handle) {
    onMain(() -> {
      DartvelMediaPlayer p = PLAYERS.remove(handle);
      if (p == null) return null;
      if (sLastStarted == p) {
        sLastStarted = null;
        DartvelMediaSession.clear();
      }
      p.player.release();
      if (p.producer != null) p.producer.release();
      return null;
    });
  }
$_json}
''';

final String _sessionSource = '''
package dev.dartvel.jni;

$_header
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import androidx.media3.common.ForwardingPlayer;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MediaMetadata;
import androidx.media3.common.Player;
import androidx.media3.session.MediaSession;
import java.util.ArrayList;
import java.util.List;

/// The lock screen, the notification's transport controls, a headset's
/// buttons. The session wraps the player in a ForwardingPlayer that queues
/// what the person pressed for Dart instead of doing it, so the controller
/// in Dart decides -- the same one a page's play button goes through.
public final class DartvelMediaSession {
  private static MediaSession sSession;
  private static Player sPlayer;
  private static String sMetadataKey;
  private static final List<String> COMMANDS = new ArrayList<>();

  static MediaSession current() {
    return sSession;
  }

  private static void command(String json) {
    COMMANDS.add(json);
  }

  /// Points the session at [player], if one is published.
  static void follow(Player player) {
    if (sSession == null || player == sPlayer) return;
    sPlayer = player;
    sSession.setPlayer(wrap(player));
  }

  private static Player wrap(Player player) {
    return new ForwardingPlayer(player) {
      @Override
      public void play() {
        command("{\\"action\\":\\"play\\"}");
      }

      @Override
      public void pause() {
        command("{\\"action\\":\\"pause\\"}");
      }

      @Override
      public void setPlayWhenReady(boolean playWhenReady) {
        command(playWhenReady ? "{\\"action\\":\\"play\\"}" : "{\\"action\\":\\"pause\\"}");
      }

      @Override
      public void stop() {
        command("{\\"action\\":\\"stop\\"}");
      }

      @Override
      public void seekTo(long positionMs) {
        command("{\\"action\\":\\"seekTo\\",\\"ms\\":" + positionMs + "}");
      }

      @Override
      public void seekTo(int mediaItemIndex, long positionMs) {
        command("{\\"action\\":\\"seekTo\\",\\"ms\\":" + positionMs + "}");
      }

      @Override
      public void seekForward() {
        command("{\\"action\\":\\"seekForward\\"}");
      }

      @Override
      public void seekBack() {
        command("{\\"action\\":\\"seekBackward\\"}");
      }

      @Override
      public void seekToNext() {
        command("{\\"action\\":\\"seekForward\\"}");
      }

      @Override
      public void seekToPrevious() {
        command("{\\"action\\":\\"seekBackward\\"}");
      }
    };
  }

  /// Puts the last-started player on the lock screen with this metadata.
  /// The position and state are the player's own, which the session reads
  /// directly; they are passed for parity with the other platforms.
  public static void publish(String title, String artist, String album,
      String artwork, boolean playing, long positionMs, long durationMs) {
    onMain(() -> {
      Context context = DartvelContext.context();
      Player player = DartvelMediaPlayer.lastStarted();
      if (context == null || player == null) return null;
      if (sSession == null) {
        sPlayer = player;
        sSession = new MediaSession.Builder(context, wrap(player))
            .setId("dartvel")
            .build();
        try {
          // The service is what keeps playing with the application in the
          // background and what posts the media notification.
          context.startService(new Intent(context, DartvelMediaService.class));
        } catch (RuntimeException error) {
          // Started from the background, which Android refuses. The
          // session still answers headset and Bluetooth buttons.
        }
        DartvelMediaService.attach(sSession);
      } else {
        follow(player);
      }
      String key = title + "\\u0000" + artist + "\\u0000" + album + "\\u0000" + artwork;
      MediaItem item = player.getCurrentMediaItem();
      if (item != null && !key.equals(sMetadataKey)) {
        sMetadataKey = key;
        MediaMetadata.Builder metadata = new MediaMetadata.Builder()
            .setTitle(title)
            .setArtist(artist)
            .setAlbumTitle(album);
        if (artwork != null && !artwork.isEmpty()) {
          metadata.setArtworkUri(Uri.parse(artwork));
        }
        player.replaceMediaItem(player.getCurrentMediaItemIndex(),
            item.buildUpon().setMediaMetadata(metadata.build()).build());
      }
      return null;
    });
  }

  /// Takes the application off the lock screen.
  public static void clear() {
    onMain(() -> {
      MediaSession session = sSession;
      sSession = null;
      sPlayer = null;
      sMetadataKey = null;
      if (session != null) {
        DartvelMediaService.detach(session);
        session.release();
      }
      return null;
    });
  }

  /// What the person pressed since the last call, as a JSON array, or null.
  public static String commands() {
    return onMain(() -> drain(COMMANDS));
  }
$_json}
''';

const String _serviceSource = '''
package dev.dartvel.jni;

$_header
import android.content.Intent;
import androidx.media3.session.MediaSession;
import androidx.media3.session.MediaSessionService;

/// The foreground service a playing DVMediaSession lives in. Media3 posts
/// the media notification and moves the service in and out of the
/// foreground as the player starts and stops.
public final class DartvelMediaService extends MediaSessionService {
  private static DartvelMediaService sRunning;
  private static MediaSession sPending;

  static void attach(MediaSession session) {
    sPending = session;
    if (sRunning != null) sRunning.addSession(session);
  }

  static void detach(MediaSession session) {
    if (sPending == session) sPending = null;
    if (sRunning != null) {
      sRunning.removeSession(session);
      sRunning.stopSelf();
    }
  }

  @Override
  public void onCreate() {
    super.onCreate();
    sRunning = this;
    if (sPending != null) addSession(sPending);
  }

  @Override
  public MediaSession onGetSession(MediaSession.ControllerInfo controller) {
    return DartvelMediaSession.current();
  }

  /// Swiped away from recents: keep going only if something is playing.
  @Override
  public void onTaskRemoved(Intent rootIntent) {
    MediaSession session = DartvelMediaSession.current();
    if (session == null || !session.getPlayer().getPlayWhenReady()) {
      stopSelf();
    }
  }

  @Override
  public void onDestroy() {
    sRunning = null;
    super.onDestroy();
  }
}
''';

final String _focusSource = '''
package dev.dartvel.jni;

$_header
import android.content.Context;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Build;

/// Android's audio focus, for DVAudioFocus. Losses are counted for Dart to
/// poll rather than delivered, because nothing here calls into Dart.
public final class DartvelAudioFocus {
  private static long sLosses = 0;
  private static AudioFocusRequest sRequest;

  private static final AudioManager.OnAudioFocusChangeListener LISTENER =
      change -> {
        if (change == AudioManager.AUDIOFOCUS_LOSS
            || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) {
          sLosses++;
        }
      };

  private static AudioManager manager() {
    Context context = DartvelContext.context();
    return context == null
        ? null
        : (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
  }

  @SuppressWarnings("deprecation")
  public static boolean request() {
    return onMain(() -> {
      AudioManager audio = manager();
      if (audio == null) return true;
      int result;
      if (Build.VERSION.SDK_INT >= 26) {
        sRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                .build())
            .setOnAudioFocusChangeListener(LISTENER)
            .build();
        result = audio.requestAudioFocus(sRequest);
      } else {
        result = audio.requestAudioFocus(LISTENER, AudioManager.STREAM_MUSIC,
            AudioManager.AUDIOFOCUS_GAIN);
      }
      return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED;
    });
  }

  @SuppressWarnings("deprecation")
  public static void abandon() {
    onMain(() -> {
      AudioManager audio = manager();
      if (audio == null) return null;
      if (Build.VERSION.SDK_INT >= 26 && sRequest != null) {
        audio.abandonAudioFocusRequest(sRequest);
      } else {
        audio.abandonAudioFocus(LISTENER);
      }
      return null;
    });
  }

  /// Losses since the last call.
  public static long losses() {
    return onMain(() -> {
      long count = sLosses;
      sLosses = 0;
      return count;
    });
  }
$_json}
''';

final String _cameraSource = '''
package dev.dartvel.jni;

$_header
import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.media.CamcorderProfile;
import android.util.Size;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.CameraState;
import androidx.camera.core.ImageCapture;
import androidx.camera.core.ImageCaptureException;
import androidx.camera.core.Preview;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.video.FallbackStrategy;
import androidx.camera.video.FileOutputOptions;
import androidx.camera.video.PendingRecording;
import androidx.camera.video.Quality;
import androidx.camera.video.QualitySelector;
import androidx.camera.video.Recorder;
import androidx.camera.video.Recording;
import androidx.camera.video.VideoCapture;
import androidx.camera.video.VideoRecordEvent;
import androidx.core.content.ContextCompat;
import androidx.lifecycle.LifecycleOwner;
import com.google.common.util.concurrent.ListenableFuture;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.view.TextureRegistry;
import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Executor;

/// CameraX bound to the resumed Flutter activity, previewing into a
/// Flutter texture. One per handle; everything on the main thread.
public final class DartvelCamera {
  private static final Map<Long, DartvelCamera> CAMERAS = new HashMap<>();
  private static long sNext = 1;

  private final TextureRegistry.SurfaceProducer producer;
  private final List<String> events = new ArrayList<>();
  private ProcessCameraProvider provider;
  private Camera camera;
  private ImageCapture imageCapture;
  private VideoCapture<Recorder> videoCapture;
  private Recording recording;
  private String lens = "back";
  private String quality = "hd720";
  private boolean surfaceReported = false;

  private DartvelCamera(TextureRegistry.SurfaceProducer producer) {
    this.producer = producer;
  }

  private void add(String event) {
    events.add(event);
  }

  private static Executor main(Context context) {
    return ContextCompat.getMainExecutor(context);
  }

  /// What the device has, from Camera2, without opening anything.
  public static String capabilities() {
    Context context = DartvelContext.context();
    if (context == null) return "{}";
    boolean back = false;
    boolean front = false;
    boolean external = false;
    boolean flash = false;
    List<String> qualities = new ArrayList<>();
    try {
      CameraManager manager =
          (CameraManager) context.getSystemService(Context.CAMERA_SERVICE);
      for (String id : manager.getCameraIdList()) {
        CameraCharacteristics c = manager.getCameraCharacteristics(id);
        Integer facing = c.get(CameraCharacteristics.LENS_FACING);
        Boolean hasFlash = c.get(CameraCharacteristics.FLASH_INFO_AVAILABLE);
        if (facing == null) continue;
        if (facing == CameraCharacteristics.LENS_FACING_BACK) {
          back = true;
          if (Boolean.TRUE.equals(hasFlash)) flash = true;
          try {
            int numeric = Integer.parseInt(id);
            if (qualities.isEmpty()) {
              if (CamcorderProfile.hasProfile(numeric, CamcorderProfile.QUALITY_480P)) qualities.add("\\"sd480\\"");
              if (CamcorderProfile.hasProfile(numeric, CamcorderProfile.QUALITY_720P)) qualities.add("\\"hd720\\"");
              if (CamcorderProfile.hasProfile(numeric, CamcorderProfile.QUALITY_1080P)) qualities.add("\\"hd1080\\"");
            }
          } catch (NumberFormatException ignored) {
            // A camera id that is not a number has no camcorder profile.
          }
        } else if (facing == CameraCharacteristics.LENS_FACING_FRONT) {
          front = true;
        } else {
          external = true;
        }
      }
    } catch (Exception error) {
      return "{\\"error\\":" + quote(String.valueOf(error.getMessage())) + "}";
    }
    StringBuilder lenses = new StringBuilder();
    if (back) lenses.append("\\"back\\"");
    if (front) lenses.append(lenses.length() > 0 ? "," : "").append("\\"front\\"");
    if (external) lenses.append(lenses.length() > 0 ? "," : "").append("\\"external\\"");
    return "{\\"lenses\\":[" + lenses + "],\\"flash\\":" + flash + ",\\"torch\\":"
        + flash + ",\\"qualities\\":[" + String.join(",", qualities) + "]}";
  }

  public static long createCamera(long engineId) {
    return onMain(() -> {
      FlutterEngine engine = FlutterEngine.engineForId(engineId);
      if (engine == null) return 0L;
      long handle = sNext++;
      CAMERAS.put(handle,
          new DartvelCamera(engine.getRenderer().createSurfaceProducer()));
      return handle;
    });
  }

  public static long cameraTextureId(long handle) {
    return onMain(() -> {
      DartvelCamera c = CAMERAS.get(handle);
      return c == null ? -1L : c.producer.id();
    });
  }

  public static void openCamera(long handle, String lens) {
    onMain(() -> {
      DartvelCamera c = CAMERAS.get(handle);
      Context context = DartvelContext.context();
      if (c == null || context == null) return null;
      c.lens = lens;
      ListenableFuture<ProcessCameraProvider> future =
          ProcessCameraProvider.getInstance(context);
      future.addListener(() -> {
        try {
          c.provider = future.get();
          c.bind(context);
        } catch (Exception error) {
          c.add("{\\"type\\":\\"failed\\",\\"message\\":"
              + quote("CameraX did not start: " + error.getMessage()) + "}");
        }
      }, main(context));
      return null;
    });
  }

  private void bind(Context context) {
    Activity activity = DartvelContext.activity();
    if (!(activity instanceof LifecycleOwner)) {
      add("{\\"type\\":\\"failed\\",\\"message\\":"
          + quote("there is no resumed Flutter activity to bind the camera to") + "}");
      return;
    }
    provider.unbindAll();
    CameraSelector selector = "front".equals(lens)
        ? CameraSelector.DEFAULT_FRONT_CAMERA
        : CameraSelector.DEFAULT_BACK_CAMERA;
    Preview preview = new Preview.Builder().build();
    surfaceReported = false;
    preview.setSurfaceProvider(main(context), request -> {
      Size size = request.getResolution();
      producer.setSize(size.getWidth(), size.getHeight());
      request.setTransformationInfoListener(main(context), info -> {
        if (surfaceReported) return;
        surfaceReported = true;
        int rotation = producer.handlesCropAndRotation() ? 0 : info.getRotationDegrees();
        boolean sideways = rotation == 90 || rotation == 270;
        add("{\\"type\\":\\"opened\\",\\"lens\\":" + quote(lens) + ",\\"width\\":"
            + (sideways ? size.getHeight() : size.getWidth()) + ",\\"height\\":"
            + (sideways ? size.getWidth() : size.getHeight()) + ",\\"rotation\\":"
            + rotation + "}");
      });
      request.provideSurface(producer.getSurface(), main(context), result -> {});
    });
    imageCapture = new ImageCapture.Builder()
        .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
        .build();
    Recorder recorder = new Recorder.Builder()
        .setQualitySelector(QualitySelector.from(qualityOf(quality),
            FallbackStrategy.lowerQualityOrHigherThan(Quality.SD)))
        .build();
    videoCapture = VideoCapture.withOutput(recorder);
    LifecycleOwner owner = (LifecycleOwner) activity;
    try {
      camera = provider.bindToLifecycle(owner, selector, preview, imageCapture,
          videoCapture);
    } catch (IllegalArgumentException tooMany) {
      // Some hardware cannot run all three at once. Photos and preview are
      // what a camera box is for; video says why when asked.
      videoCapture = null;
      camera = provider.bindToLifecycle(owner, selector, preview, imageCapture);
    }
    camera.getCameraInfo().getCameraState().observe(owner, state -> {
      if (state.getError() != null && state.getType() == CameraState.Type.CLOSED) {
        add("{\\"type\\":\\"disconnected\\"}");
      }
    });
  }

  private static Quality qualityOf(String name) {
    switch (name) {
      case "sd480": return Quality.SD;
      case "hd1080": return Quality.FHD;
      default: return Quality.HD;
    }
  }

  public static void closeCamera(long handle) {
    onMain(() -> {
      DartvelCamera c = CAMERAS.get(handle);
      if (c == null) return null;
      if (c.recording != null) {
        c.recording.stop();
        c.recording = null;
      }
      if (c.provider != null) c.provider.unbindAll();
      c.camera = null;
      c.add("{\\"type\\":\\"closed\\"}");
      return null;
    });
  }

  public static void takePhoto(long handle, String path, String flash) {
    onMain(() -> {
      DartvelCamera c = CAMERAS.get(handle);
      Context context = DartvelContext.context();
      if (c == null || context == null || c.imageCapture == null) return null;
      c.imageCapture.setFlashMode("on".equals(flash)
          ? ImageCapture.FLASH_MODE_ON
          : "auto".equals(flash) ? ImageCapture.FLASH_MODE_AUTO
              : ImageCapture.FLASH_MODE_OFF);
      c.imageCapture.takePicture(
          new ImageCapture.OutputFileOptions.Builder(new File(path)).build(),
          main(context),
          new ImageCapture.OnImageSavedCallback() {
            @Override
            public void onImageSaved(ImageCapture.OutputFileResults results) {
              c.add("{\\"type\\":\\"photo\\",\\"path\\":" + quote(path) + "}");
            }

            @Override
            public void onError(ImageCaptureException error) {
              c.add("{\\"type\\":\\"failed\\",\\"message\\":"
                  + quote("the photo failed: " + error.getMessage()) + "}");
            }
          });
      return null;
    });
  }

  public static void startRecording(long handle, String path, String quality,
      boolean audio) {
    onMain(() -> {
      DartvelCamera c = CAMERAS.get(handle);
      Context context = DartvelContext.context();
      if (c == null || context == null) return null;
      if (!quality.equals(c.quality) && c.provider != null) {
        c.quality = quality;
        c.bind(context);
      }
      if (c.videoCapture == null) {
        c.add("{\\"type\\":\\"failed\\",\\"message\\":"
            + quote("this camera cannot record video alongside its preview") + "}");
        return null;
      }
      PendingRecording pending = c.videoCapture.getOutput().prepareRecording(
          context, new FileOutputOptions.Builder(new File(path)).build());
      if (audio && ContextCompat.checkSelfPermission(context,
          Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
        pending = pending.withAudioEnabled();
      }
      c.recording = pending.start(main(context), event -> {
        if (event instanceof VideoRecordEvent.Start) {
          c.add("{\\"type\\":\\"recordingStarted\\"}");
        } else if (event instanceof VideoRecordEvent.Finalize) {
          VideoRecordEvent.Finalize done = (VideoRecordEvent.Finalize) event;
          int error = done.getError();
          if (error == VideoRecordEvent.Finalize.ERROR_NONE
              || error == VideoRecordEvent.Finalize.ERROR_DURATION_LIMIT_REACHED
              || error == VideoRecordEvent.Finalize.ERROR_FILE_SIZE_LIMIT_REACHED
              || error == VideoRecordEvent.Finalize.ERROR_SOURCE_INACTIVE) {
            long ms = done.getRecordingStats().getRecordedDurationNanos() / 1000000L;
            c.add("{\\"type\\":\\"recordingStopped\\",\\"ms\\":" + ms + "}");
          } else {
            c.add("{\\"type\\":\\"failed\\",\\"message\\":" + quote("the recording failed ("
                + error + "): " + done.getCause()) + "}");
          }
        }
      });
      return null;
    });
  }

  public static void stopRecording(long handle) {
    onMain(() -> {
      DartvelCamera c = CAMERAS.get(handle);
      if (c != null && c.recording != null) {
        c.recording.stop();
        c.recording = null;
      }
      return null;
    });
  }

  public static void setTorch(long handle, boolean on) {
    onMain(() -> {
      DartvelCamera c = CAMERAS.get(handle);
      if (c != null && c.camera != null) c.camera.getCameraControl().enableTorch(on);
      return null;
    });
  }

  public static String pollCamera(long handle) {
    return onMain(() -> {
      DartvelCamera c = CAMERAS.get(handle);
      return c == null ? null : drain(c.events);
    });
  }

  public static void disposeCamera(long handle) {
    onMain(() -> {
      DartvelCamera c = CAMERAS.remove(handle);
      if (c == null) return null;
      if (c.recording != null) c.recording.stop();
      if (c.provider != null) c.provider.unbindAll();
      c.producer.release();
      return null;
    });
  }
$_json}
''';
