/// `dragDrop.accept` and `dragDrop.stop` in a browser.
///
/// A drop on a page carries File objects with names, types and contents and
/// no paths, so each arrives in [DVDropEvent.files] with its bytes. Text
/// dropped from another page arrives as [DVDropEvent.text].
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../drag_drop.dart';
import 'web_media_js.dart';

abstract final class DVWebDragDrop {
  static const Set<String> bindings = <String>{'dragDrop.accept', 'dragDrop.stop'};

  static JSFunction? _onDragOver;
  static JSFunction? _onDragLeave;
  static JSFunction? _onDrop;
  static int _depth = 0;

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) register) {
    register('dragDrop.accept', (Object? arguments) {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      final List<Object?> types = (map['types'] as List?) ?? const <Object?>['files', 'text'];
      _listen(files: types.contains('files'), text: types.contains('text'));
      return true;
    });
    register('dragDrop.stop', (Object? _) {
      _unlisten();
      return true;
    });
  }

  static void _listen({required bool files, required bool text}) {
    _unlisten();
    _depth = 0;
    // Without preventDefault on dragover the browser opens the file itself
    // and the page never sees a drop.
    _onDragOver = ((web.DragEvent event) {
      event.preventDefault();
      event.dataTransfer?.dropEffect = 'copy';
    }).toJS;
    final JSFunction enter = ((web.DragEvent event) {
      event.preventDefault();
      if (_depth++ == 0) DVDragDrop.dispatchDragOver(true);
    }).toJS;
    _onDragLeave = ((web.DragEvent event) {
      if (--_depth <= 0) {
        _depth = 0;
        DVDragDrop.dispatchDragOver(false);
      }
    }).toJS;
    _onDrop = ((web.DragEvent event) {
      event.preventDefault();
      _depth = 0;
      DVDragDrop.dispatchDragOver(false);
      unawaited(_deliver(event, files: files, text: text));
    }).toJS;
    web.window.addEventListener('dragover', _onDragOver);
    web.window.addEventListener('dragenter', enter);
    _enter = enter;
    web.window.addEventListener('dragleave', _onDragLeave);
    web.window.addEventListener('drop', _onDrop);
  }

  static JSFunction? _enter;

  static void _unlisten() {
    if (_onDragOver != null) web.window.removeEventListener('dragover', _onDragOver);
    if (_enter != null) web.window.removeEventListener('dragenter', _enter);
    if (_onDragLeave != null) web.window.removeEventListener('dragleave', _onDragLeave);
    if (_onDrop != null) web.window.removeEventListener('drop', _onDrop);
    _onDragOver = _enter = _onDragLeave = _onDrop = null;
  }

  static Future<void> _deliver(web.DragEvent event, {required bool files, required bool text}) async {
    final web.DataTransfer? transfer = event.dataTransfer;
    if (transfer == null) return;
    final List<DVDroppedFile> dropped = <DVDroppedFile>[];
    if (files) {
      final web.FileList list = transfer.files;
      for (int index = 0; index < list.length; index++) {
        final web.File? file = list.item(index);
        if (file == null) continue;
        final Map<String, Object?> described = await DVWebMedia.describe(file);
        dropped.add(DVDroppedFile.fromMap(described));
      }
    }
    final String dropText = text ? transfer.getData('text/plain') : '';
    DVDragDrop.dispatch(DVDropEvent(
      files: dropped,
      text: dropText.isEmpty ? null : dropText,
      x: event.clientX.toDouble(),
      y: event.clientY.toDouble(),
    ));
  }
}
