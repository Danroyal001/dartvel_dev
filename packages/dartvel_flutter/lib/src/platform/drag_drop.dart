/// Drag and drop: what the desktop dropped onto the window.
///
/// The desktop capability list names drag and drop, and nothing implemented
/// it -- a file dragged from a file manager onto a Dartvel window landed
/// nowhere. A window accepts drops of the kinds it says it takes; each drop
/// arrives as what was dropped and where, and what to do with it is the
/// application's. Everything goes through the `dragDrop.*` bindings and
/// fails naming the binding where there is none, as every desktop API does.
library;

import 'dart:async';

import '../../dartvel_flutter.dart' show DVNativeBridge;

/// What a window will take a drop of.
enum DVDropType {
  /// Files, which the desktop sends as a list of URIs.
  files,

  /// Plain text, which a browser or an editor sends.
  text,
}

/// One drop onto the window.
class DVDropEvent {
  const DVDropEvent({this.paths = const <String>[], this.text, this.x = 0, this.y = 0});

  /// The files dropped, in the order the desktop sent them.
  final List<String> paths;

  /// The text dropped, when text was dropped rather than files.
  final String? text;

  /// Where the drop landed, in the window's own coordinates.
  final double x;
  final double y;

  /// Whether anything was actually dropped. A drop with neither files nor
  /// text is the desktop offering nothing.
  bool get isEmpty => paths.isEmpty && (text == null || text!.isEmpty);

  factory DVDropEvent.fromMap(Map<Object?, Object?> map) => DVDropEvent(
        paths: <String>[
          for (final Object? p in (map['paths'] as List?) ?? const <Object?>[]) '$p',
        ],
        text: map['text'] as String?,
        x: map['x'] is num ? (map['x']! as num).toDouble() : 0,
        y: map['y'] is num ? (map['y']! as num).toDouble() : 0,
      );

  @override
  String toString() => 'DVDropEvent(paths: $paths, text: $text, at: $x,$y)';
}

class DVDragDrop {
  const DVDragDrop();

  static void Function(DVDropEvent event)? _onDrop;
  static bool _accepting = false;
  static final StreamController<DVDropEvent> _dropped =
      StreamController<DVDropEvent>.broadcast();

  /// Every drop the window took.
  Stream<DVDropEvent> get dropped => _dropped.stream;

  /// For platform bindings: the desktop dropped something. A drop after the
  /// window stopped accepting reaches nobody -- the desktop can deliver one
  /// that was already in flight -- and an empty drop is not a drop.
  static void dispatch(DVDropEvent event) {
    if (!_accepting || event.isEmpty) return;
    _onDrop?.call(event);
    _dropped.add(event);
  }

  static void reset() {
    _onDrop = null;
    _accepting = false;
  }

  /// Whether the window is taking drops.
  static bool get accepting => _accepting;

  /// Takes drops of [types] onto the window, running [onDrop] for each.
  ///
  /// Both kinds by default: a window that takes files usually takes a link
  /// dragged from a browser too, and refusing text silently is the kind of
  /// half-capability that looks like a broken window.
  Future<void> accept({
    List<DVDropType> types = const <DVDropType>[DVDropType.files, DVDropType.text],
    void Function(DVDropEvent event)? onDrop,
  }) async {
    final handled = await DVNativeBridge.require<bool>(
      'dragDrop.accept',
      <String, Object?>{'types': <String>[for (final DVDropType t in types) t.name]},
    );
    if (!handled) throw StateError('Native drag and drop binding rejected accept.');
    _onDrop = onDrop;
    _accepting = true;
  }

  /// Stops taking drops.
  Future<void> stop() async {
    final handled = await DVNativeBridge.require<bool>('dragDrop.stop');
    if (!handled) throw StateError('Native drag and drop binding rejected stop.');
    _onDrop = null;
    _accepting = false;
  }
}
