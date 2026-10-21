/// Drag and drop on iOS and iPadOS, through the `DartvelDragDrop` Swift class
/// `dartvel build ios` compiles into the application, messaged by name
/// through the Objective-C runtime.
///
/// The bridge calls back with a `strdup`ed JSON string per event, on the
/// main thread, through a [NativeCallable.listener]; this side decodes it
/// and frees it. Dropped files were copied into the application's temporary
/// directory before the drop was reported, because `NSItemProvider` deletes
/// its own copy when its callback returns.
library dartvel_flutter.platform.ios.drag_drop_ffi;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Directory, File;

import 'package:dartvel_core/dartvel.dart' show dvIosDragDropClass;
import 'package:ffi/ffi.dart';

import '../drag_drop.dart';
import 'ios_drag_drop_shapes.dart';

typedef _GetClassNative = Pointer<Void> Function(Pointer<Utf8> name);
typedef _GetClassDart = Pointer<Void> Function(Pointer<Utf8> name);
typedef _SendVoidNative = Void Function(Pointer<Void> receiver, Pointer<Void> selector);
typedef _SendVoidDart = void Function(Pointer<Void> receiver, Pointer<Void> selector);
typedef _SendPointerNative = Void Function(
    Pointer<Void> receiver, Pointer<Void> selector, Pointer<Void> argument);
typedef _SendPointerDart = void Function(
    Pointer<Void> receiver, Pointer<Void> selector, Pointer<Void> argument);
typedef _EventNative = Void Function(Pointer<Utf8> json);

class DVIosDragDrop {
  const DVIosDragDrop._();

  static const Set<String> implemented = <String>{
    'dragDrop.accept',
    'dragDrop.stop',
    'dragDrop.setPending',
  };

  static NativeCallable<_EventNative>? _events;

  /// Why the bridge cannot be reached, or null when it can.
  static String? lastFailure;

  /// Registers the bindings when the bridge is compiled in; false when it
  /// is not (an application built with plain `flutter build`).
  static bool register(DynamicLibrary objc, void Function(String, FutureOr<Object?> Function(Object?)) bind) {
    final _GetClassDart getClass =
        objc.lookupFunction<_GetClassNative, _GetClassDart>('objc_getClass');
    final _GetClassDart selector =
        objc.lookupFunction<_GetClassNative, _GetClassDart>('sel_registerName');
    final _SendVoidDart sendVoid =
        objc.lookupFunction<_SendVoidNative, _SendVoidDart>('objc_msgSend');
    final _SendPointerDart sendPointer =
        objc.lookupFunction<_SendPointerNative, _SendPointerDart>('objc_msgSend');

    Pointer<Void> named(_GetClassDart lookup, String name) {
      final Pointer<Utf8> native = name.toNativeUtf8();
      try {
        return lookup(native);
      } finally {
        malloc.free(native);
      }
    }

    final Pointer<Void> bridge = named(getClass, dvIosDragDropClass);
    if (bridge == nullptr) {
      lastFailure = 'the class $dvIosDragDropClass is not in this application. '
          '`dartvel build ios` compiles it in; plain `flutter build` does not.';
      return false;
    }
    lastFailure = null;

    bind('dragDrop.accept', (Object? _) {
      _events ??= NativeCallable<_EventNative>.listener(_receive);
      sendPointer(bridge, named(selector, 'start:'), _events!.nativeFunction.cast<Void>());
      return true;
    });
    bind('dragDrop.stop', (Object? _) {
      sendVoid(bridge, named(selector, 'stop'));
      return true;
    });
    bind('dragDrop.setPending', (Object? payload) async {
      final Object? withFiles = payload is Map ? await _withFilesWritten(payload) : null;
      final Pointer<Utf8> json =
          withFiles == null ? nullptr : jsonEncode(withFiles).toNativeUtf8();
      try {
        sendPointer(bridge, named(selector, 'setPending:'), json.cast<Void>());
      } finally {
        if (json != nullptr) malloc.free(json);
      }
      return true;
    });
    return true;
  }

  static void _receive(Pointer<Utf8> native) {
    final String json;
    try {
      json = native.toDartString();
    } finally {
      // strdup'ed by the bridge, so malloc's.
      malloc.free(native);
    }
    final Object? decoded = jsonDecode(json);
    if (decoded is! Map) return;
    switch (decoded['kind']) {
      case 'hover':
        DVDragDrop.dispatchHover(
          ((decoded['x'] as num?) ?? 0).toDouble(),
          ((decoded['y'] as num?) ?? 0).toDouble(),
        );
      case 'leave':
        DVDragDrop.dispatchLeave();
      case 'drop':
        DVDragDrop.dispatch(DVDropEvent.fromMap(dvIosDropMap(decoded)));
    }
  }

  /// Files a drag carries as bytes, written to the temporary directory so
  /// the bridge can hand UIKit a file URL for each.
  static Future<Map<Object?, Object?>> _withFilesWritten(Map<Object?, Object?> payload) async {
    final List<Object?> files = (payload['files'] as List?) ?? const <Object?>[];
    if (files.isEmpty) return payload;
    final Directory folder =
        await Directory('${Directory.systemTemp.path}/dartvel-drag').create(recursive: true);
    final List<Map<String, Object?>> written = <Map<String, Object?>>[];
    for (final Object? raw in files) {
      if (raw is! Map) continue;
      String? path = raw['path'] as String?;
      final List<Object?>? bytes = raw['bytes'] as List?;
      if (bytes != null) {
        final String name = '${raw['name']}'.replaceAll(RegExp(r'[/\\]|\.\.'), '_');
        path = '${folder.path}/$name';
        await File(path).writeAsBytes(bytes.cast<int>(), flush: true);
      }
      if (path == null) continue;
      written.add(<String, Object?>{'name': raw['name'], 'mimeType': raw['mimeType'], 'path': path});
    }
    return <Object?, Object?>{...payload, 'files': written};
  }
}
