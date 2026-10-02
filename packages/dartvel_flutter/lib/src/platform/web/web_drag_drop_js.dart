/// Drag and drop in a browser: HTML drag events and `DataTransfer`.
///
/// Drops: the page listens for `dragover` (which has to be cancelled for the
/// browser to allow a drop at all) and `drop`, and reads what the drag
/// carried -- files, `text/uri-list` links and `text/plain` -- off its
/// `DataTransfer`. Files are read when the application asks, through the
/// browser `File` object, never up front.
///
/// Dragging out: a browser only starts a drag from an element the pointer
/// went down on that is `draggable`, and fills the drag in that element's
/// `dragstart`. Flutter draws into one element, so a draggable widget marks
/// that element draggable for the press it started ([setPending]), and the
/// `dragstart` that follows is filled from the payload: text, links, and
/// files as `File` objects plus Chrome's `DownloadURL` so a file can land on
/// the desktop.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../drag_drop.dart';
import 'web_drag_drop_shapes.dart';

class DVWebDragDrop {
  const DVWebDragDrop._();

  static const Set<String> implemented = <String>{
    'dragDrop.accept',
    'dragDrop.stop',
    'dragDrop.setPending',
  };

  static JSFunction? _over;
  static JSFunction? _leave;
  static JSFunction? _drop;
  static JSFunction? _dragStart;
  static JSFunction? _reset;
  static Map<Object?, Object?>? _pending;
  static final List<String> _objectUrls = <String>[];

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind) {
    bind('dragDrop.accept', (Object? _) {
      _listen();
      return true;
    });
    bind('dragDrop.stop', (Object? _) {
      _unlisten();
      return true;
    });
    bind('dragDrop.setPending', (Object? payload) {
      _setPending(payload is Map ? payload : null);
      return true;
    });
  }

  /// Flutter's element: where coordinates are measured from and where a
  /// drag out has to start.
  static web.HTMLElement get _host {
    final web.Element? view = web.document.querySelector('flutter-view');
    return (view as web.HTMLElement?) ?? web.document.body!;
  }

  static ({double x, double y}) _local(web.DragEvent event) {
    final web.DOMRect rect = _host.getBoundingClientRect();
    return (x: event.clientX - rect.left, y: event.clientY - rect.top);
  }

  static void _listen() {
    if (_drop != null) return;
    _over = ((web.DragEvent event) {
      // Cancelled, or the browser refuses the drop and opens the file.
      event.preventDefault();
      event.dataTransfer?.dropEffect = 'copy';
      final ({double x, double y}) at = _local(event);
      DVDragDrop.dispatchHover(at.x, at.y);
    }).toJS;
    _leave = ((web.DragEvent event) {
      // Only when leaving the page, not when crossing from one child to
      // another inside it, which also fires dragleave.
      if (event.relatedTarget == null) DVDragDrop.dispatchLeave();
    }).toJS;
    _drop = ((web.DragEvent event) {
      event.preventDefault();
      final web.DataTransfer? transfer = event.dataTransfer;
      if (transfer == null) return;
      final ({double x, double y}) at = _local(event);
      final List<web.File> files = <web.File>[
        for (var index = 0; index < transfer.files.length; index++) transfer.files.item(index)!,
      ];
      DVDragDrop.dispatch(DVDropEvent.fromMap(
        dvWebDropMap(
          files: <Map<String, Object?>>[
            for (final web.File file in files)
              <String, Object?>{'name': file.name, 'mimeType': file.type, 'size': file.size},
          ],
          uriList: transfer.getData('text/uri-list'),
          text: transfer.getData('text/plain'),
          x: at.x,
          y: at.y,
        ),
        readers: (int index) async {
          final JSArrayBuffer buffer = await files[index].arrayBuffer().toDart;
          return buffer.toDart.asUint8List();
        },
      ));
    }).toJS;
    web.window.addEventListener('dragover', _over);
    web.window.addEventListener('dragleave', _leave);
    web.window.addEventListener('drop', _drop);
  }

  static void _unlisten() {
    if (_drop == null) return;
    web.window.removeEventListener('dragover', _over);
    web.window.removeEventListener('dragleave', _leave);
    web.window.removeEventListener('drop', _drop);
    _over = _leave = _drop = null;
  }

  static void _setPending(Map<Object?, Object?>? payload) {
    _pending = payload;
    final web.HTMLElement host = _host;
    if (payload == null) {
      host.draggable = false;
      return;
    }
    // Draggable for this press only: the browser decides at the press
    // whether a movement is a drag, and decides it from this attribute.
    host.draggable = true;
    _dragStart ??= ((web.DragEvent event) {
      final Map<Object?, Object?>? pending = _pending;
      final web.DataTransfer? transfer = event.dataTransfer;
      if (pending == null || transfer == null) return;
      dvFillWebDrag(pending, transfer, _objectUrls);
    }).toJS;
    _reset ??= ((web.Event _) {
      _pending = null;
      _host.draggable = false;
    }).toJS;
    host.addEventListener('dragstart', _dragStart);
    // Every way the press can end: released without dragging, or a drag
    // that finished either way.
    web.window.addEventListener('pointerup', _reset);
    web.window.addEventListener('dragend', _reset);
  }
}

/// Fills a browser drag from a payload's JSON.
void dvFillWebDrag(Map<Object?, Object?> payload, web.DataTransfer transfer, List<String> objectUrls) {
  transfer.effectAllowed = 'copy';
  final List<String> urls = <String>[
    for (final Object? url in (payload['urls'] as List?) ?? const <Object?>[]) '$url',
  ];
  final String? text = payload['text'] as String?;
  if (urls.isNotEmpty) transfer.setData('text/uri-list', urls.join('\r\n'));
  final String plain = text ?? urls.join('\n');
  if (plain.isNotEmpty) transfer.setData('text/plain', plain);
  for (final Object? raw in (payload['files'] as List?) ?? const <Object?>[]) {
    if (raw is! Map) continue;
    final List<int>? bytes = (raw['bytes'] as List?)?.cast<int>();
    if (bytes == null) continue;
    final String name = '${raw['name']}';
    final String type = '${raw['mimeType'] ?? 'application/octet-stream'}';
    final web.Blob blob = web.Blob(
      <JSAny>[Uint8List.fromList(bytes).toJS].toJS,
      web.BlobPropertyBag(type: type),
    );
    transfer.items.add(web.File(<JSAny>[blob].toJS, name, web.FilePropertyBag(type: type)));
    // Chrome's way to drop a file onto the desktop or a file manager.
    final String objectUrl = web.URL.createObjectURL(blob);
    objectUrls.add(objectUrl);
    transfer.setData('DownloadURL', '$type:$name:$objectUrl');
  }
}
