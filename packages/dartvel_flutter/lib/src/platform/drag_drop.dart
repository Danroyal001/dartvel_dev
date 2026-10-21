/// Drag and drop on every target: what was dropped onto the application,
/// and what the application drags out to another one.
///
/// Drops arrive the same way everywhere -- a file manager on the desktop, an
/// app beside this one in split screen or a freeform window on Android, Files
/// or Photos in Split View or Slide Over on iPadOS, another tab or the
/// desktop onto a browser page -- as one [DVDropEvent]: the files, the links,
/// the text, and where it landed. A whole window can take drops
/// ([DVDragDrop.accept]); so can one widget (`DVModifier().dropTarget(...)`),
/// in which case the drop goes to the widget under it.
///
/// Dragging out ([DVDragDrop.startDrag], `DVModifier().draggable(...)`) hands
/// text, links or files to the platform's own drag, where the platform has one
/// another application can receive.
///
/// Everything goes through the `dragDrop.*` bindings. Where a target has no
/// drag and drop at all, [DVDragDrop.chooseInstead] opens the file picker and
/// delivers what was chosen to the same handler, so the feature works there
/// too, by a different gesture.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import '../../dartvel_flutter.dart' show DVNativeBridge;
import 'incoming_file.dart';

/// What a window or widget will take a drop of.
enum DVDropType {
  /// Files: from a file manager, Files, Photos, or a browser's file drag.
  files,

  /// Plain text.
  text,

  /// Links: a URL dragged out of a browser or another app.
  urls,
}

/// One drop.
class DVDropEvent {
  const DVDropEvent({
    List<String> paths = const <String>[],
    List<DVIncomingFile> files = const <DVIncomingFile>[],
    this.urls = const <Uri>[],
    this.text,
    this.x = 0,
    this.y = 0,
  }) : _paths = paths,
       _files = files;

  final List<String> _paths;
  final List<DVIncomingFile> _files;

  /// The files dropped, in the order the platform sent them.
  List<DVIncomingFile> get files => <DVIncomingFile>[
    ..._files,
    for (final String path in _paths) DVIncomingFile.atPath(path),
  ];

  /// The links dropped.
  final List<Uri> urls;

  /// The text dropped, when text was dropped.
  final String? text;

  /// Where the drop landed, in logical pixels from the window's top left.
  final double x;
  final double y;

  /// The filesystem paths of the files dropped, where the platform gave any.
  List<String> get paths => <String>[
    for (final DVIncomingFile file in _files)
      if (file.path != null) file.path!,
    ..._paths,
  ];

  Offset get position => Offset(x, y);

  /// Whether anything was dropped. A drop carrying nothing is not a drop.
  bool get isEmpty =>
      _files.isEmpty &&
      _paths.isEmpty &&
      urls.isEmpty &&
      (text == null || text!.isEmpty);

  /// Whether this drop carries anything [types] admits.
  bool carriesAnyOf(Set<DVDropType> types) =>
      (types.contains(DVDropType.files) && files.isNotEmpty) ||
      (types.contains(DVDropType.urls) && urls.isNotEmpty) ||
      (types.contains(DVDropType.text) && text != null && text!.isNotEmpty);

  /// The same drop, with what [types] does not admit left out.
  DVDropEvent onlyOf(Set<DVDropType> types) => DVDropEvent(
    files: types.contains(DVDropType.files) ? files : const <DVIncomingFile>[],
    urls: types.contains(DVDropType.urls) ? urls : const <Uri>[],
    text: types.contains(DVDropType.text) ? text : null,
    x: x,
    y: y,
  );

  /// The shape every binding hands over: `files` (maps with name, mimeType,
  /// path, uri, size), or bare `paths`, plus `urls`, `text`, `x`, `y`.
  /// [readers] reads a file the platform gave no path for, by its index.
  factory DVDropEvent.fromMap(
    Map<Object?, Object?> map, {
    Future<List<int>> Function(int index)? readers,
  }) {
    final List<DVIncomingFile> files = <DVIncomingFile>[];
    final List<Object?> rawFiles = (map['files'] as List?) ?? const <Object?>[];
    for (var index = 0; index < rawFiles.length; index++) {
      final Object? raw = rawFiles[index];
      if (raw is! Map) continue;
      final String? path = raw['path'] as String?;
      final String? uri = raw['uri'] as String?;
      final String name =
          (raw['name'] as String?) ??
          (path != null
              ? DVIncomingFile.atPath(path).name
              : (uri != null
                    ? Uri.parse(uri).pathSegments.lastOrNull ?? uri
                    : 'file'));
      final int fileIndex = index;
      // A binding may hand the contents over in the map itself.
      final Object? rawBytes = raw['bytes'];
      final Uint8List? bytes = rawBytes is List
          ? dvAsUint8List(<int>[
              for (final Object? byte in rawBytes) (byte! as num).toInt(),
            ])
          : null;
      files.add(
        DVIncomingFile(
          name: name,
          mimeType: (raw['mimeType'] as String?) ?? dvMimeTypeFor(name),
          path: path,
          uri: uri == null ? null : Uri.tryParse(uri),
          size: raw['size'] is num
              ? (raw['size']! as num).toInt()
              : bytes?.length,
          read: bytes != null
              ? () async => bytes
              : (readers == null || path != null
                    ? null
                    : () async => dvAsUint8List(await readers(fileIndex))),
        ),
      );
    }
    for (final Object? path in (map['paths'] as List?) ?? const <Object?>[]) {
      if (path is String && path.isNotEmpty)
        files.add(DVIncomingFile.atPath(path));
    }
    return DVDropEvent(
      files: files,
      urls: <Uri>[
        for (final Object? url in (map['urls'] as List?) ?? const <Object?>[])
          if (url is String &&
              Uri.tryParse(url) != null &&
              Uri.parse(url).hasScheme)
            Uri.parse(url),
      ],
      text: map['text'] as String?,
      x: map['x'] is num ? (map['x']! as num).toDouble() : 0,
      y: map['y'] is num ? (map['y']! as num).toDouble() : 0,
    );
  }

  @override
  String toString() =>
      'DVDropEvent(files: $files, urls: $urls, text: $text, at: $x,$y)';
}

/// [bytes] as a [Uint8List], without copying when it already is one.
Uint8List dvAsUint8List(List<int> bytes) =>
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

/// What a drag out of the application carries.
class DVDragPayload {
  const DVDragPayload({
    this.text,
    this.urls = const <Uri>[],
    this.files = const <DVOutgoingFile>[],
  });

  final String? text;
  final List<Uri> urls;
  final List<DVOutgoingFile> files;

  bool get isEmpty =>
      (text == null || text!.isEmpty) && urls.isEmpty && files.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    if (text != null) 'text': text,
    'urls': <String>[for (final Uri url in urls) url.toString()],
    'files': <Map<String, Object?>>[
      for (final DVOutgoingFile file in files) file.toJson(),
    ],
  };
}

/// A file a drag carries out: its bytes, or a path the binding can read.
class DVOutgoingFile {
  const DVOutgoingFile({
    required this.name,
    this.mimeType,
    this.path,
    this.bytes,
  });

  final String name;
  final String? mimeType;
  final String? path;
  final List<int>? bytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'mimeType': mimeType ?? dvMimeTypeFor(name) ?? 'application/octet-stream',
    if (path != null) 'path': path,
    if (bytes != null) 'bytes': bytes,
  };
}

/// One widget's claim on drops that land inside it.
class DVDropTargetRegistration {
  DVDropTargetRegistration({
    required this.bounds,
    required this.types,
    required this.onDrop,
    this.onHover,
  });

  /// The widget's rectangle in window coordinates, asked at drop time so a
  /// widget that moved or scrolled is found where it is now.
  final Rect? Function() bounds;
  Set<DVDropType> types;
  final void Function(DVDropEvent event) onDrop;
  final void Function(bool hovering)? onHover;
  bool hovering = false;
}

class DVDragDrop {
  const DVDragDrop();

  static void Function(DVDropEvent event)? _onDrop;
  static bool _accepting = false;
  static bool _nativeActive = false;
  static bool _nativeAllTypes = false;
  static Set<DVDropType> _types = DVDropType.values.toSet();
  static final StreamController<DVDropEvent> _dropped =
      StreamController<DVDropEvent>.broadcast();
  static final List<DVDropTargetRegistration> _targets =
      <DVDropTargetRegistration>[];
  static DVDragPayload? _pending;
  static final StreamController<bool> _over =
      StreamController<bool>.broadcast();
  static bool _windowOver = false;

  /// Every drop the application took, whichever window or widget took it.
  Stream<DVDropEvent> get dropped => _dropped.stream;

  /// True when a drag comes over the window, false when it leaves or is
  /// dropped, while the window is accepting (so a page can show where to
  /// drop). One true per drag, however far it moves.
  Stream<bool> get draggingOver => _over.stream;

  /// Whether this target can take drops at all. Where it cannot,
  /// [chooseInstead] is the way in.
  bool get supported => DVNativeBridge.isRegistered('dragDrop.accept');

  /// Whether this target can drag something out to another application.
  bool get canDragOut =>
      DVNativeBridge.isRegistered('dragDrop.startDrag') ||
      DVNativeBridge.isRegistered('dragDrop.setPending');

  /// Whether Dart starts a drag out (`dragDrop.startDrag`). Where only
  /// `dragDrop.setPending` exists (a browser) the platform starts its own
  /// drag from the press, and [startDrag] cannot start one.
  bool get startsDrags => DVNativeBridge.isRegistered('dragDrop.startDrag');

  /// For platform bindings: something was dropped at the event's position.
  ///
  /// The smallest widget target under the drop that admits what it carries
  /// takes it; otherwise the window's handler does, if the window is
  /// accepting. A drop that nothing admits reaches nobody, and an empty drop
  /// is not a drop.
  static void dispatch(DVDropEvent event) {
    _endWindowOver();
    if (event.isEmpty) return;
    _clearHover();
    final DVDropTargetRegistration? target = _targetAt(event.position, event);
    if (target != null) {
      final DVDropEvent admitted = event.onlyOf(target.types);
      target.onDrop(admitted);
      _dropped.add(admitted);
      return;
    }
    if (!_accepting || !event.carriesAnyOf(_types)) return;
    final admitted = event.onlyOf(_types);
    _onDrop?.call(admitted);
    _dropped.add(admitted);
  }

  /// For platform bindings: a drag is over the window at ([x], [y]). Lets a
  /// widget target show that it would take the drop.
  static void dispatchHover(double x, double y) {
    if (_accepting && !_windowOver) {
      _windowOver = true;
      _over.add(true);
    }
    final Offset point = Offset(x, y);
    final DVDropTargetRegistration? over = _targetAt(point, null);
    for (final DVDropTargetRegistration target in _targets) {
      final bool now = identical(target, over);
      if (target.hovering != now) {
        target.hovering = now;
        target.onHover?.call(now);
      }
    }
  }

  /// For platform bindings: the drag left the window, or was cancelled.
  static void dispatchLeave() {
    _endWindowOver();
    _clearHover();
  }

  static void _endWindowOver() {
    if (!_windowOver) return;
    _windowOver = false;
    _over.add(false);
  }

  static void _clearHover() {
    for (final DVDropTargetRegistration target in _targets) {
      if (target.hovering) {
        target.hovering = false;
        target.onHover?.call(false);
      }
    }
  }

  static DVDropTargetRegistration? _targetAt(Offset point, DVDropEvent? event) {
    DVDropTargetRegistration? best;
    double bestArea = double.infinity;
    for (final DVDropTargetRegistration target in _targets) {
      final Rect? rect = target.bounds();
      if (rect == null || !rect.contains(point)) continue;
      if (event != null && !event.carriesAnyOf(target.types)) continue;
      final double area = rect.width * rect.height;
      if (area <= bestArea) {
        best = target;
        bestArea = area;
      }
    }
    return best;
  }

  /// For widgets: claim drops that land inside [registration]'s bounds.
  /// Turns on the window's drop handling where the platform needs that.
  static Future<void> addTarget(DVDropTargetRegistration registration) async {
    _targets.add(registration);
    if (DVNativeBridge.isRegistered('dragDrop.accept') &&
        (!_nativeActive || !_nativeAllTypes)) {
      // Claim before awaiting so widgets mounting together share one listener.
      _nativeActive = true;
      _nativeAllTypes = true;
      try {
        final handled = await DVNativeBridge.require<bool>('dragDrop.accept', {
          'types': [for (final type in DVDropType.values) type.name],
        });
        if (!handled)
          throw StateError('Native drag and drop binding rejected accept.');
      } catch (_) {
        _nativeActive = false;
        _nativeAllTypes = false;
        _targets.remove(registration);
        rethrow;
      }
    }
  }

  static void removeTarget(DVDropTargetRegistration registration) {
    _targets.remove(registration);
    if (!_accepting && _targets.isEmpty) unawaited(_stopNative());
  }

  static Future<void> _stopNative() async {
    if (!_nativeActive) return;
    _nativeActive = false;
    _nativeAllTypes = false;
    final handled = await DVNativeBridge.require<bool>('dragDrop.stop');
    if (!handled)
      throw StateError('Native drag and drop binding rejected stop.');
  }

  static void reset() {
    _onDrop = null;
    _accepting = false;
    _nativeActive = false;
    _nativeAllTypes = false;
    _types = DVDropType.values.toSet();
    _targets.clear();
    _pending = null;
    _windowOver = false;
  }

  /// Whether the window is taking drops.
  static bool get accepting => _accepting;

  /// Takes drops of [types] anywhere on the window, running [onDrop] for each.
  ///
  /// Every kind by default: a window that takes files usually takes a link
  /// dragged from a browser too, and refusing text silently looks broken.
  Future<void> accept({
    List<DVDropType> types = DVDropType.values,
    void Function(DVDropEvent event)? onDrop,
  }) async {
    final handled = await DVNativeBridge.require<bool>(
      'dragDrop.accept',
      <String, Object?>{
        'types': <String>[
          for (final t in _targets.isEmpty ? types : DVDropType.values) t.name,
        ],
      },
    );
    if (!handled)
      throw StateError('Native drag and drop binding rejected accept.');
    _onDrop = onDrop;
    _types = types.toSet();
    _nativeActive = true;
    _nativeAllTypes =
        _targets.isNotEmpty || _types.containsAll(DVDropType.values);
    _accepting = true;
  }

  /// Stops taking drops on the window. Widget targets keep theirs.
  Future<void> stop() async {
    _endWindowOver();
    _onDrop = null;
    _accepting = false;
    if (_targets.isEmpty) await _stopNative();
  }

  /// What a drag starting now will carry. Set by a draggable widget when a
  /// pointer goes down on it, because some platforms ask for the payload at
  /// the moment their own drag begins rather than when Dart starts it.
  static DVDragPayload? get pendingPayload => _pending;
  static set pendingPayload(DVDragPayload? payload) {
    _pending = payload;
    if (DVNativeBridge.isRegistered('dragDrop.setPending')) {
      unawaited(
        DVNativeBridge.invoke<bool>('dragDrop.setPending', payload?.toJson()),
      );
    }
  }

  /// Starts a drag out of the application carrying [payload].
  ///
  /// Returns false where the platform declined to start one (no pointer
  /// down, or nothing to carry), and where the platform starts drags itself
  /// from a press and only takes the payload ahead of time (a browser: the
  /// payload is handed over as [pendingPayload] instead). Throws naming the
  /// binding where the target has no drag out at all; check [canDragOut]
  /// first to decide what to offer.
  Future<bool> startDrag(
    DVDragPayload payload, {
    double x = 0,
    double y = 0,
  }) async {
    if (payload.isEmpty) return false;
    if (!startsDrags && DVNativeBridge.isRegistered('dragDrop.setPending')) {
      pendingPayload = payload;
      return false;
    }
    return DVNativeBridge.require<bool>('dragDrop.startDrag', <String, Object?>{
      ...payload.toJson(),
      'x': x,
      'y': y,
    });
  }

  /// Where a target has no drag and drop, the same files arrive by choosing
  /// them: opens the file picker and delivers the choice as a drop, to the
  /// window handler and the [dropped] stream. Returns the event, or null when
  /// nothing was chosen.
  Future<DVDropEvent?> chooseInstead({
    bool multiple = true,
    String type = 'any',
  }) async {
    Object? chosen;
    if (DVNativeBridge.isRegistered('dialogs.openFile')) {
      chosen = await DVNativeBridge.require<Object?>(
        'dialogs.openFile',
        <String, Object?>{'multiple': multiple},
      );
    } else {
      chosen = await DVNativeBridge.require<List<Object?>>(
        'media.pick',
        <String, Object?>{'type': type, 'multiple': multiple},
      );
    }
    final List<Object?> items = chosen is List
        ? chosen
        : (chosen == null ? const <Object?>[] : <Object?>[chosen]);
    final DVDropEvent event = DVDropEvent.fromMap(<String, Object?>{
      'files': <Object?>[
        for (final Object? item in items)
          if (item is String)
            <String, Object?>{'path': item}
          else if (item is Map)
            item,
      ],
    });
    if (event.isEmpty) return null;
    _onDrop?.call(event);
    _dropped.add(event);
    return event;
  }
}
