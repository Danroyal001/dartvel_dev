/// Linux playback and capture through GStreamer, over dart:ffi.
///
/// No platform channel and no plugin: direct calls into libgstreamer, the
/// library the eLinux embedder already builds its video player on. GStreamer's
/// bus is polled from a Dart timer rather than watched from a GLib main loop,
/// because a callback from a GStreamer streaming thread cannot enter Dart.
///
/// What is here: `playbin` for files, assets and URLs, with position,
/// duration, buffering, seeking, volume, completion and errors; and audio
/// recording into Opus/Ogg, WAV or AAC/MP4 through whichever encoders are
/// installed. What is not: frames drawn into Flutter (video decodes and its
/// audio plays under the box's poster, and the capability report says
/// `video: false`), and camera capture.
library dartvel_flutter.platform.linux.media;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:ffi/ffi.dart';

import '../../media/media_box.dart';

typedef _PV = Pointer<Void>;

// GstState
const int _stateNull = 1;
const int _statePaused = 3;
const int _statePlaying = 4;

// GstMessageType
const int _msgEos = 1 << 0;
const int _msgError = 1 << 1;
const int _msgBuffering = 1 << 5;
const int _msgStateChanged = 1 << 6;
const int _msgDurationChanged = 1 << 18;
const int _msgAsyncDone = 1 << 21;

// GstParseFlags
const int _parseFatalErrors = 1 << 0;

const int _formatTime = 3;
const int _seekFlush = 1 << 0;
const int _seekAccurate = 1 << 1;

// GstMessage: a GstMiniObject (64 bytes on LP64), then the type, the
// timestamp and the source object. Stable across GStreamer 1.x.
const int _messageTypeOffset = 64;
const int _messageSourceOffset = 80;

final class _Gst {
  _Gst(DynamicLibrary gst, DynamicLibrary gobject, DynamicLibrary glib)
      : initCheck = gst.lookupFunction<Int32 Function(_PV, _PV, _PV),
            int Function(_PV, _PV, _PV)>('gst_init_check'),
        factoryFind = gst.lookupFunction<_PV Function(Pointer<Utf8>),
            _PV Function(Pointer<Utf8>)>('gst_element_factory_find'),
        factoryMake = gst.lookupFunction<
            _PV Function(Pointer<Utf8>, Pointer<Utf8>),
            _PV Function(Pointer<Utf8>, Pointer<Utf8>)>(
          'gst_element_factory_make',
        ),
        parseLaunchFull = gst.lookupFunction<
            _PV Function(Pointer<Utf8>, _PV, Int32, Pointer<_PV>),
            _PV Function(Pointer<Utf8>, _PV, int, Pointer<_PV>)>(
          'gst_parse_launch_full',
        ),
        parseContextNew = gst.lookupFunction<_PV Function(), _PV Function()>(
            'gst_parse_context_new'),
        parseContextFree = gst.lookupFunction<Void Function(_PV),
            void Function(_PV)>('gst_parse_context_free'),
        parseContextMissing = gst.lookupFunction<
            Pointer<Pointer<Utf8>> Function(_PV),
            Pointer<Pointer<Utf8>> Function(_PV)>(
          'gst_parse_context_get_missing_elements',
        ),
        setState = gst.lookupFunction<Int32 Function(_PV, Int32),
            int Function(_PV, int)>('gst_element_set_state'),
        getBus = gst.lookupFunction<_PV Function(_PV), _PV Function(_PV)>(
            'gst_element_get_bus'),
        binByName = gst.lookupFunction<_PV Function(_PV, Pointer<Utf8>),
            _PV Function(_PV, Pointer<Utf8>)>('gst_bin_get_by_name'),
        pop = gst.lookupFunction<_PV Function(_PV, Uint64, Int32),
            _PV Function(_PV, int, int)>('gst_bus_timed_pop_filtered'),
        miniUnref = gst.lookupFunction<Void Function(_PV), void Function(_PV)>(
            'gst_mini_object_unref'),
        objectUnref = gst.lookupFunction<Void Function(_PV),
            void Function(_PV)>('gst_object_unref'),
        queryPosition = gst.lookupFunction<
            Int32 Function(_PV, Int32, Pointer<Int64>),
            int Function(_PV, int, Pointer<Int64>)>(
          'gst_element_query_position',
        ),
        queryDuration = gst.lookupFunction<
            Int32 Function(_PV, Int32, Pointer<Int64>),
            int Function(_PV, int, Pointer<Int64>)>(
          'gst_element_query_duration',
        ),
        seekSimple = gst.lookupFunction<Int32 Function(_PV, Int32, Int32, Int64),
            int Function(_PV, int, int, int)>('gst_element_seek_simple'),
        parseError = gst.lookupFunction<
            Void Function(_PV, Pointer<_PV>, Pointer<Pointer<Utf8>>),
            void Function(_PV, Pointer<_PV>, Pointer<Pointer<Utf8>>)>(
          'gst_message_parse_error',
        ),
        parseBuffering = gst.lookupFunction<Void Function(_PV, Pointer<Int32>),
            void Function(_PV, Pointer<Int32>)>('gst_message_parse_buffering'),
        parseStateChanged = gst.lookupFunction<
            Void Function(_PV, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>),
            void Function(_PV, Pointer<Int32>, Pointer<Int32>,
                Pointer<Int32>)>('gst_message_parse_state_changed'),
        sendEvent = gst.lookupFunction<Int32 Function(_PV, _PV),
            int Function(_PV, _PV)>('gst_element_send_event'),
        eventEos = gst.lookupFunction<_PV Function(), _PV Function()>(
            'gst_event_new_eos'),
        getClock = gst.lookupFunction<_PV Function(_PV), _PV Function(_PV)>(
            'gst_element_get_clock'),
        clockTime = gst.lookupFunction<Uint64 Function(_PV), int Function(_PV)>(
            'gst_clock_get_time'),
        baseTime = gst.lookupFunction<Uint64 Function(_PV), int Function(_PV)>(
            'gst_element_get_base_time'),
        setString = gobject.lookupFunction<
            Void Function(_PV, Pointer<Utf8>, VarArgs<(Pointer<Utf8>, _PV)>),
            void Function(_PV, Pointer<Utf8>, Pointer<Utf8>, _PV)>(
          'g_object_set',
        ),
        setPointer = gobject.lookupFunction<
            Void Function(_PV, Pointer<Utf8>, VarArgs<(_PV, _PV)>),
            void Function(_PV, Pointer<Utf8>, _PV, _PV)>('g_object_set'),
        setBool = gobject.lookupFunction<
            Void Function(_PV, Pointer<Utf8>, VarArgs<(Int32, _PV)>),
            void Function(_PV, Pointer<Utf8>, int, _PV)>('g_object_set'),
        setDouble = gobject.lookupFunction<
            Void Function(_PV, Pointer<Utf8>, VarArgs<(Double, _PV)>),
            void Function(_PV, Pointer<Utf8>, double, _PV)>('g_object_set'),
        errorFree = glib.lookupFunction<Void Function(_PV), void Function(_PV)>(
            'g_error_free'),
        gFree = glib.lookupFunction<Void Function(_PV), void Function(_PV)>(
            'g_free'),
        strfreev = glib.lookupFunction<Void Function(Pointer<Pointer<Utf8>>),
            void Function(Pointer<Pointer<Utf8>>)>('g_strfreev');

  final int Function(_PV, _PV, _PV) initCheck;
  final _PV Function(Pointer<Utf8>) factoryFind;
  final _PV Function(Pointer<Utf8>, Pointer<Utf8>) factoryMake;
  final _PV Function(Pointer<Utf8>, _PV, int, Pointer<_PV>) parseLaunchFull;
  final _PV Function() parseContextNew;
  final void Function(_PV) parseContextFree;
  final Pointer<Pointer<Utf8>> Function(_PV) parseContextMissing;
  final void Function(Pointer<Pointer<Utf8>>) strfreev;

  /// Builds [description], or throws [DVGStreamerPipelineError].
  ///
  /// Never `gst_parse_launch` with no error out-parameter: given an element
  /// that is not installed it drops the element and returns what is left --
  /// on a machine with libgstreamer and no plugins, a lone filesink with no
  /// bus, which the caller then polled for thirty seconds. Fatal errors and a
  /// parse context turn that into a refusal naming the missing elements.
  _PV launch(String description) => using((Arena arena) {
        final _PV context = parseContextNew();
        final Pointer<_PV> error = arena<_PV>()..value = nullptr;
        final _PV built = parseLaunchFull(
            description.toNativeUtf8(allocator: arena),
            context,
            _parseFatalErrors,
            error);
        final List<String> missing = <String>[];
        if (context != nullptr) {
          final Pointer<Pointer<Utf8>> names = parseContextMissing(context);
          if (names != nullptr) {
            for (int i = 0; names[i] != nullptr; i++) {
              missing.add(names[i].toDartString());
            }
            strfreev(names);
          }
          parseContextFree(context);
        }
        String? message;
        if (error.value != nullptr) {
          message = gerrorText(error.value);
          errorFree(error.value);
        }
        if (message == null && built != nullptr) return built;
        if (built != nullptr) objectUnref(built);
        throw DVGStreamerPipelineError(
          description,
          missing.isNotEmpty
              ? 'these GStreamer elements are not installed: '
                  '${missing.join(', ')}'
              : message ?? 'GStreamer could not build $description',
          missingElements: List<String>.unmodifiable(missing),
        );
      });

  /// A GError's message: a GQuark and an int, then the string.
  static String gerrorText(_PV error) =>
      (error.cast<Pointer<Utf8>>() + 1).value.toDartString();
  final int Function(_PV, int) setState;
  final _PV Function(_PV) getBus;
  final _PV Function(_PV, Pointer<Utf8>) binByName;
  final _PV Function(_PV, int, int) pop;
  final void Function(_PV) miniUnref;
  final void Function(_PV) objectUnref;
  final int Function(_PV, int, Pointer<Int64>) queryPosition;
  final int Function(_PV, int, Pointer<Int64>) queryDuration;
  final int Function(_PV, int, int, int) seekSimple;
  final void Function(_PV, Pointer<_PV>, Pointer<Pointer<Utf8>>) parseError;
  final void Function(_PV, Pointer<Int32>) parseBuffering;
  final void Function(_PV, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>)
      parseStateChanged;
  final int Function(_PV, _PV) sendEvent;
  final _PV Function() eventEos;
  final _PV Function(_PV) getClock;
  final int Function(_PV) clockTime;
  final int Function(_PV) baseTime;

  /// How long a playing pipeline has been running, by its own clock. What a
  /// live recording's length is: a pipeline ending in filesink answers no
  /// position query in time.
  Duration? runningTime(_PV element) {
    final _PV clock = getClock(element);
    if (clock == nullptr) return null;
    try {
      final int now = clockTime(clock) - baseTime(element);
      return now < 0 ? null : Duration(microseconds: now ~/ 1000);
    } finally {
      objectUnref(clock);
    }
  }
  final void Function(_PV, Pointer<Utf8>, Pointer<Utf8>, _PV) setString;
  final void Function(_PV, Pointer<Utf8>, _PV, _PV) setPointer;
  final void Function(_PV, Pointer<Utf8>, int, _PV) setBool;
  final void Function(_PV, Pointer<Utf8>, double, _PV) setDouble;
  final void Function(_PV) errorFree;
  final void Function(_PV) gFree;

  _PV make(String factory) => using((Arena arena) =>
      factoryMake(factory.toNativeUtf8(allocator: arena), nullptr));

  void setStringProperty(_PV object, String name, String value) =>
      using((Arena arena) => setString(
            object,
            name.toNativeUtf8(allocator: arena),
            value.toNativeUtf8(allocator: arena),
            nullptr,
          ));

  void setPointerProperty(_PV object, String name, _PV value) => using(
      (Arena arena) => setPointer(
          object, name.toNativeUtf8(allocator: arena), value, nullptr));

  void setBoolProperty(_PV object, String name, bool value) =>
      using((Arena arena) => setBool(object,
          name.toNativeUtf8(allocator: arena), value ? 1 : 0, nullptr));

  void setDoubleProperty(_PV object, String name, double value) => using(
      (Arena arena) => setDouble(
          object, name.toNativeUtf8(allocator: arena), value, nullptr));

  Duration? position(_PV element) => using((Arena arena) {
        final Pointer<Int64> out = arena<Int64>();
        return queryPosition(element, _formatTime, out) != 0 && out.value >= 0
            ? Duration(microseconds: out.value ~/ 1000)
            : null;
      });

  Duration? duration(_PV element) => using((Arena arena) {
        final Pointer<Int64> out = arena<Int64>();
        return queryDuration(element, _formatTime, out) != 0 && out.value >= 0
            ? Duration(microseconds: out.value ~/ 1000)
            : null;
      });

  String errorMessage(_PV message) => using((Arena arena) {
        final Pointer<_PV> error = arena<_PV>();
        final Pointer<Pointer<Utf8>> debug = arena<Pointer<Utf8>>();
        parseError(message, error, debug);
        final String text = error.value == nullptr
            ? 'GStreamer reported an error'
            : gerrorText(error.value);
        if (error.value != nullptr) errorFree(error.value);
        if (debug.value != nullptr) gFree(debug.value.cast());
        return text;
      });

  static int typeOf(_PV message) =>
      (message.cast<Uint32>() + _messageTypeOffset ~/ 4).value;

  static _PV sourceOf(_PV message) =>
      (message.cast<_PV>() + _messageSourceOffset ~/ 8).value;
}

/// A pipeline GStreamer could not build: an element that is not installed,
/// a description that does not parse, or one that is not a pipeline at all.
final class DVGStreamerPipelineError implements Exception {
  const DVGStreamerPipelineError(this.description, this.reason,
      {this.missingElements = const <String>[]});

  final String description;
  final String reason;

  /// The element factories GStreamer's registry does not have, as GStreamer
  /// named them. Empty when the failure is something else.
  final List<String> missingElements;

  @override
  String toString() => 'DVGStreamerPipelineError: $reason';
}

/// GStreamer, loaded once for the process.
abstract final class DVGStreamer {
  /// Why [description] cannot be built here, or null when it can. Builds and
  /// discards it; an element left in the NULL state opens no device.
  static DVGStreamerPipelineError? check(String description) {
    if (!load()) {
      return DVGStreamerPipelineError(description, 'GStreamer is not installed');
    }
    try {
      _gst!.objectUnref(_gst!.launch(description));
      return null;
    } on DVGStreamerPipelineError catch (error) {
      return error;
    }
  }

  /// The elements [description] names that are not installed, from the
  /// registry. Empty when GStreamer itself is not installed: see [load].
  static List<String> missingElements(String description) =>
      check(description)?.missingElements ?? const <String>[];

  static _Gst? _gst;
  static bool _tried = false;

  /// Loads and initialises GStreamer. False when it is not installed.
  static bool load() {
    if (_tried) return _gst != null;
    _tried = true;
    try {
      final _Gst gst = _Gst(
        DynamicLibrary.open('libgstreamer-1.0.so.0'),
        DynamicLibrary.open('libgobject-2.0.so.0'),
        DynamicLibrary.open('libglib-2.0.so.0'),
      );
      if (gst.initCheck(nullptr, nullptr, nullptr) == 0) return false;
      _gst = gst;
      return true;
    } on ArgumentError {
      return false;
    }
  }

  static _Gst get _api {
    if (!load()) throw StateError('GStreamer is not installed.');
    return _gst!;
  }

  /// Whether an element factory named [name] is installed.
  static bool hasElement(String name) {
    if (!load()) return false;
    return using((Arena arena) =>
        _gst!.factoryFind(name.toNativeUtf8(allocator: arena)) != nullptr);
  }

  /// Runs a `gst-launch`-style pipeline until it ends. Throws on an error,
  /// and throws [DVGStreamerPipelineError] before running when the pipeline
  /// cannot be built.
  static Future<void> runToEos(
    String description, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final _Gst gst = _api;
    final _PV pipeline = gst.launch(description);
    final _PV bus = gst.getBus(pipeline);
    if (bus == nullptr) {
      // One element parses to that element, not a pipeline, and nothing
      // posts to a bus it does not have.
      gst.objectUnref(pipeline);
      throw DVGStreamerPipelineError(
          description, '$description is a single element with no bus, '
          'not a pipeline');
    }
    gst.setState(pipeline, _statePlaying);
    final DateTime end = DateTime.now().add(timeout);
    try {
      while (true) {
        final _PV message = gst.pop(bus, 0, _msgEos | _msgError);
        if (message != nullptr) {
          final int type = _Gst.typeOf(message);
          final String? error =
              type == _msgError ? gst.errorMessage(message) : null;
          gst.miniUnref(message);
          if (error != null) throw StateError(error);
          return;
        }
        if (DateTime.now().isAfter(end)) {
          throw TimeoutException('pipeline did not finish', timeout);
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    } finally {
      gst.setState(pipeline, _stateNull);
      gst.objectUnref(bus);
      gst.objectUnref(pipeline);
    }
  }
}

/// A `playbin` player.
final class DVGStreamerPlayer implements DVMediaPlayerBackend {
  DVGStreamerPlayer({
    this.audioSink,
    this.videoSink,
    this.pollInterval = const Duration(milliseconds: 50),
  });

  /// The audio output element, or null for the first installed of
  /// pipewiresink, pulsesink, alsasink and autoaudiosink.
  final String? audioSink;

  /// The video output element, or null for fakesink: frames are decoded to
  /// keep audio and video in step but not drawn into Flutter.
  final String? videoSink;

  final Duration pollInterval;

  static const List<String> _audioOutputs = <String>[
    'pipewiresink',
    'pulsesink',
    'alsasink',
    'autoaudiosink',
  ];

  /// What GStreamer on this machine can do.
  static DVMediaBackendCapabilities probe() => DVMediaBackendCapabilities(
        adaptiveStreaming: (DVGStreamer.hasElement('hlsdemux') ||
                DVGStreamer.hasElement('hlsdemux2')) &&
            (DVGStreamer.hasElement('dashdemux') ||
                DVGStreamer.hasElement('dashdemux2')),
        // A desktop process keeps running in the background.
        backgroundAudio: true,
        video: false,
      );

  final StreamController<DVMediaBackendEvent> _events =
      StreamController<DVMediaBackendEvent>.broadcast();

  _PV _playbin = nullptr;
  _PV _bus = nullptr;
  Timer? _timer;
  bool _ready = false;
  bool _released = false;
  int _completedSeek = 0;
  int? _pendingSeek;
  int _lastState = 0;

  /// The elements [open] would need that are not installed: playbin, the
  /// audio output -- [audioSink], or every default when none of them is --
  /// and [videoSink] or fakesink. Empty when this machine can play.
  static List<String> missingElements({String? audioSink, String? videoSink}) {
    final String video = videoSink ?? 'fakesink';
    return <String>[
      if (!DVGStreamer.hasElement('playbin')) 'playbin',
      if (audioSink != null && !DVGStreamer.hasElement(audioSink))
        audioSink
      else if (audioSink == null && !_audioOutputs.any(DVGStreamer.hasElement))
        ..._audioOutputs,
      if (!DVGStreamer.hasElement(video)) video,
    ];
  }

  /// Whether the bus is still being polled.
  bool get isPolling => _timer?.isActive ?? false;

  /// Whether the pipeline has been torn down.
  bool get isReleased => _released;

  @override
  DVMediaBackendCapabilities get capabilities => probe();

  @override
  Stream<DVMediaBackendEvent> get events => _events.stream;

  void _emit(DVMediaBackendEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  Future<void> open(DVMediaSource source, {Object? license}) async {
    if (!DVGStreamer.load()) {
      _emit(const DVMediaFailed('GStreamer is not installed'));
      return;
    }
    if (license != null) {
      _emit(const DVMediaFailed(
          'the GStreamer player has no content-protection support'));
      return;
    }
    final _Gst gst = DVGStreamer._api;

    // Every element is looked up before one is made, so a missing one fails
    // the open with its name instead of leaving a half-built player polling.
    final List<String> missing =
        missingElements(audioSink: audioSink, videoSink: videoSink);
    if (missing.isNotEmpty) {
      final bool noOutput =
          audioSink == null && _audioOutputs.every(missing.contains);
      final List<String> named = <String>[
        ...missing.where((String e) => !noOutput || !_audioOutputs.contains(e)),
        if (noOutput)
          'an audio output (pipewiresink, pulsesink, alsasink or '
              'autoaudiosink)',
      ];
      _emit(DVMediaFailed(
          'these GStreamer elements are not installed: ${named.join(', ')}'));
      return;
    }
    final String audioName = audioSink ??
        _audioOutputs.firstWhere(DVGStreamer.hasElement);
    final String videoName = videoSink ?? 'fakesink';

    final _PV audio = gst.make(audioName);
    final _PV video = gst.make(videoName);
    final _PV playbin = gst.make('playbin');
    if (audio == nullptr || video == nullptr || playbin == nullptr) {
      for (final _PV made in <_PV>[audio, video, playbin]) {
        if (made != nullptr) gst.objectUnref(made);
      }
      _emit(DVMediaFailed('GStreamer could not create playbin, $audioName '
          'and $videoName'));
      return;
    }
    for (final (_PV sink, String name) in <(_PV, String)>[
      (audio, audioName),
      (video, videoName),
    ]) {
      // A fakesink that does not sync runs as fast as the decoder can go,
      // and a position that races to the end is not playback.
      if (name == 'fakesink') gst.setBoolProperty(sink, 'sync', true);
    }

    _playbin = playbin;
    gst.setStringProperty(playbin, 'uri', _uriFor(source));
    gst.setPointerProperty(playbin, 'audio-sink', audio);
    gst.setPointerProperty(playbin, 'video-sink', video);
    _bus = gst.getBus(playbin);
    gst.setState(playbin, _statePaused);
    _timer = Timer.periodic(pollInterval, (_) => _poll());
  }

  static String _uriFor(DVMediaSource source) => switch (source.kind) {
        DVMediaSourceKind.url => source.reference,
        DVMediaSourceKind.file => Uri.file(source.reference).toString(),
        // A Linux bundle keeps assets beside the executable.
        DVMediaSourceKind.asset => Uri.file(
                '${File(Platform.resolvedExecutable).parent.path}/data/'
                'flutter_assets/${source.reference}')
            .toString(),
      };

  void _poll() {
    if (_released || _playbin == nullptr) return;
    final _Gst gst = DVGStreamer._api;
    while (true) {
      final _PV message = gst.pop(_bus, 0, -1);
      if (message == nullptr) break;
      try {
        _handle(gst, message);
      } finally {
        gst.miniUnref(message);
      }
      if (_released) return;
    }
    if (_ready && _lastState == _statePlaying) {
      final Duration? at = gst.position(_playbin);
      if (at != null) _emit(DVMediaPosition(at, seek: _completedSeek));
    }
  }

  void _handle(_Gst gst, _PV message) {
    switch (_Gst.typeOf(message)) {
      case _msgError:
        _emit(DVMediaFailed(gst.errorMessage(message)));
      case _msgEos:
        _emit(const DVMediaCompleted());
      case _msgAsyncDone:
        if (!_ready) {
          _ready = true;
          _emit(DVMediaReady(duration: gst.duration(_playbin) ?? Duration.zero));
        }
        final int? seek = _pendingSeek;
        if (seek != null) {
          _pendingSeek = null;
          _completedSeek = seek;
          _emit(DVMediaSeekCompleted(
              seek, gst.position(_playbin) ?? Duration.zero));
        }
      case _msgDurationChanged:
        final Duration? duration = gst.duration(_playbin);
        if (_ready && duration != null) {
          _emit(DVMediaReady(duration: duration));
        }
      case _msgBuffering:
        using((Arena arena) {
          final Pointer<Int32> percent = arena<Int32>();
          gst.parseBuffering(message, percent);
          if (percent.value < 100) _emit(const DVMediaBuffering());
        });
      case _msgStateChanged:
        if (_Gst.sourceOf(message) != _playbin) return;
        using((Arena arena) {
          final Pointer<Int32> old = arena<Int32>();
          final Pointer<Int32> now = arena<Int32>();
          final Pointer<Int32> pending = arena<Int32>();
          gst.parseStateChanged(message, old, now, pending);
          _lastState = now.value;
          if (now.value == _statePlaying) {
            _emit(const DVMediaPlaying());
          } else if (now.value == _statePaused &&
              old.value == _statePlaying) {
            _emit(const DVMediaPaused());
          }
        });
    }
  }

  void _require() {
    if (_released || _playbin == nullptr) {
      throw StateError('This GStreamer player is not open.');
    }
  }

  @override
  Future<void> play() async {
    _require();
    DVGStreamer._api.setState(_playbin, _statePlaying);
  }

  @override
  Future<void> pause() async {
    _require();
    DVGStreamer._api.setState(_playbin, _statePaused);
  }

  @override
  Future<void> seek(Duration position, int generation) async {
    _require();
    final _Gst gst = DVGStreamer._api;
    _pendingSeek = generation;
    final bool accepted = gst.seekSimple(_playbin, _formatTime,
            _seekFlush | _seekAccurate, position.inMicroseconds * 1000) !=
        0;
    if (!accepted) {
      // Nothing will confirm a seek GStreamer refused. Confirm where playback
      // actually is, so the controller does not wait forever or believe the
      // target.
      _pendingSeek = null;
      _completedSeek = generation;
      _emit(DVMediaSeekCompleted(
          generation, gst.position(_playbin) ?? Duration.zero));
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _require();
    DVGStreamer._api.setDoubleProperty(_playbin, 'volume', volume);
  }

  @override
  Future<void> dispose() async {
    if (_released) return;
    _released = true;
    _timer?.cancel();
    _timer = null;
    if (_playbin != nullptr) {
      final _Gst gst = DVGStreamer._api;
      gst.setState(_playbin, _stateNull);
      if (_bus != nullptr) gst.objectUnref(_bus);
      gst.objectUnref(_playbin);
      _bus = nullptr;
      _playbin = nullptr;
    }
    await _events.close();
  }
}

/// Audio recording through a GStreamer pipeline.
final class DVGStreamerCapture implements DVCaptureBackend {
  DVGStreamerCapture({
    this.audioSource,
    this.pollInterval = const Duration(milliseconds: 20),
  });

  /// A pipeline fragment for the microphone, or null for the first installed
  /// of pipewiresrc, pulsesrc, alsasrc and autoaudiosrc.
  final String? audioSource;

  final Duration pollInterval;

  static const List<String> _microphones = <String>[
    'pipewiresrc',
    'pulsesrc',
    'alsasrc',
    'autoaudiosrc',
  ];

  static String? _aacEncoder() => <String>['avenc_aac', 'voaacenc', 'fdkaacenc']
      .cast<String?>()
      .firstWhere((String? e) => DVGStreamer.hasElement(e!),
          orElse: () => null);

  /// The elements between the microphone and the file, for [format]. One
  /// list for both [probe] and [start], so a format is never reported that
  /// the pipeline built for it cannot run.
  static List<String> _chain(DVAudioFormat format) => switch (format) {
        DVAudioFormat.opus => <String>[
            'audioconvert',
            'audioresample',
            'opusenc',
            'oggmux',
          ],
        DVAudioFormat.wav => <String>['audioconvert', 'wavenc'],
        DVAudioFormat.aac => <String>[
            'audioconvert',
            'audioresample',
            _aacEncoder() ?? 'avenc_aac',
            'mp4mux',
          ],
      };

  /// What this machine can record, from the elements installed.
  static DVCaptureCapabilities probe({String? audioSource}) {
    if (!DVGStreamer.load()) return DVCaptureCapabilities.none;
    return DVCaptureCapabilities(
      // A source fragment is built and discarded, so one naming an element
      // that is not installed is reported as no microphone.
      microphone: audioSource != null
          ? DVGStreamer.check(audioSource) == null
          : _microphones.any(DVGStreamer.hasElement),
      audioFormats: <DVAudioFormat>{
        for (final DVAudioFormat format in DVAudioFormat.values)
          if (<String>[..._chain(format), 'filesink']
              .every(DVGStreamer.hasElement))
            format,
      },
    );
  }

  final StreamController<DVCaptureBackendEvent> _events =
      StreamController<DVCaptureBackendEvent>.broadcast();

  _PV _pipeline = nullptr;
  _PV _bus = nullptr;
  Timer? _timer;
  bool _started = false;
  bool _stopped = false;
  Duration _recorded = Duration.zero;
  DateTime? _eosDeadline;

  /// Whether the bus is still being polled.
  bool get isPolling => _timer?.isActive ?? false;

  @override
  DVCaptureCapabilities get capabilities =>
      probe(audioSource: audioSource);

  @override
  Stream<DVCaptureBackendEvent> get events => _events.stream;

  void _emit(DVCaptureBackendEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  Future<void> start(DVCaptureRequest request, String outputPath) async {
    if (!DVGStreamer.load()) {
      _emit(const DVCaptureFailed('GStreamer is not installed'));
      return;
    }
    if (request.kind != DVCaptureKind.audio) {
      _emit(const DVCaptureFailed(
          'video capture is not implemented for GStreamer'));
      return;
    }
    final String? source = audioSource ??
        _microphones.cast<String?>().firstWhere(
            (String? e) => DVGStreamer.hasElement(e!),
            orElse: () => null);
    if (source == null) {
      _emit(const DVCaptureFailed('no microphone source element is installed'));
      return;
    }
    final _Gst gst = DVGStreamer._api;
    final String description =
        '$source ! ${_chain(request.audioFormat!).join(' ! ')} ! '
        'filesink name=dvsink';
    final _PV pipeline;
    try {
      pipeline = gst.launch(description);
    } on DVGStreamerPipelineError catch (error) {
      // Failed before a timer exists: nothing polls a bus that is not there.
      _emit(DVCaptureFailed(error.reason));
      return;
    }
    final _PV bus = gst.getBus(pipeline);
    final _PV sink = using((Arena arena) =>
        gst.binByName(pipeline, 'dvsink'.toNativeUtf8(allocator: arena)));
    if (bus == nullptr || sink == nullptr) {
      if (sink != nullptr) gst.objectUnref(sink);
      if (bus != nullptr) gst.objectUnref(bus);
      gst.objectUnref(pipeline);
      _emit(DVCaptureFailed('could not build the pipeline $description'));
      return;
    }
    _pipeline = pipeline;
    _bus = bus;
    // Set as a property rather than written into the description, so a path
    // is never parsed as pipeline syntax. filesink opens the reserved file
    // for writing without recreating it, which keeps its 0600 mode.
    gst.setStringProperty(sink, 'location', outputPath);
    gst.objectUnref(sink);
    gst.setState(pipeline, _statePlaying);
    _timer = Timer.periodic(pollInterval, (_) => _poll());
  }

  void _poll() {
    if (_pipeline == nullptr) return;
    final _Gst gst = DVGStreamer._api;
    while (true) {
      final _PV message = gst.pop(_bus, 0, -1);
      if (message == nullptr) break;
      try {
        switch (_Gst.typeOf(message)) {
          case _msgStateChanged:
            if (_Gst.sourceOf(message) == _pipeline && !_started) {
              using((Arena arena) {
                final Pointer<Int32> old = arena<Int32>();
                final Pointer<Int32> now = arena<Int32>();
                final Pointer<Int32> pending = arena<Int32>();
                gst.parseStateChanged(message, old, now, pending);
                if (now.value == _statePlaying) {
                  _started = true;
                  _emit(const DVCaptureStarted());
                }
              });
            }
          case _msgEos:
            _finish();
            return;
          case _msgError:
            final String error = gst.errorMessage(message);
            _teardown();
            _emit(DVCaptureFailed(error));
            return;
        }
      } finally {
        gst.miniUnref(message);
      }
    }
    if (_started && !_stopped) {
      _recorded = gst.runningTime(_pipeline) ?? _recorded;
    }
    final DateTime? deadline = _eosDeadline;
    if (deadline != null && DateTime.now().isAfter(deadline)) {
      // The muxer never finished. Close anyway: an unfinalised file is better
      // than a microphone left open.
      _finish();
    }
  }

  void _finish() {
    if (_stopped && _pipeline == nullptr) return;
    _stopped = true;
    _teardown();
    _emit(DVCaptureStopped(_recorded));
  }

  void _teardown() {
    _timer?.cancel();
    _timer = null;
    if (_pipeline == nullptr) return;
    final _Gst gst = DVGStreamer._api;
    gst.setState(_pipeline, _stateNull);
    if (_bus != nullptr) gst.objectUnref(_bus);
    gst.objectUnref(_pipeline);
    _bus = nullptr;
    _pipeline = nullptr;
  }

  @override
  Future<void> stop() async {
    if (_pipeline == nullptr || _stopped) return;
    final _Gst gst = DVGStreamer._api;
    _recorded = gst.runningTime(_pipeline) ?? _recorded;
    _stopped = true;
    // End of stream lets the muxer write its trailer; the file is playable
    // only after it arrives on the bus.
    gst.sendEvent(_pipeline, gst.eventEos());
    _eosDeadline = DateTime.now().add(const Duration(seconds: 5));
  }

  @override
  Future<void> abort() async {
    if (_pipeline == nullptr) return;
    _recorded = DVGStreamer._api.runningTime(_pipeline) ?? _recorded;
    _finish();
  }

  @override
  Future<void> dispose() async {
    _teardown();
    await _events.close();
  }
}

/// Registers the GStreamer player and recorder with [DVMediaBackends].
abstract final class DVLinuxMedia {
  /// False when GStreamer is not installed; nothing is registered then, and a
  /// media box reports that no player is bound.
  static bool register() {
    if (!DVGStreamer.load()) return false;
    DVMediaBackends.registerPlayer(
        (DVMediaSource source, DVMediaKind kind) => DVGStreamerPlayer());
    DVMediaBackends.registerCapture(
      capabilities: DVGStreamerCapture.probe(),
      backend: DVGStreamerCapture.new,
      directory: captureDirectory(),
    );
    return true;
  }

  /// `$XDG_DATA_HOME/<executable>/captures`, the per-user data directory.
  static String captureDirectory() {
    final Map<String, String> env = Platform.environment;
    final String base = env['XDG_DATA_HOME']?.isNotEmpty ?? false
        ? env['XDG_DATA_HOME']!
        : '${env['HOME'] ?? Directory.systemTemp.path}/.local/share';
    final String app = File(Platform.resolvedExecutable).uri.pathSegments.last;
    return '$base/$app/captures';
  }
}
