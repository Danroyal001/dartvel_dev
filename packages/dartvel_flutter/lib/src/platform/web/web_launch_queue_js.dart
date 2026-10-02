/// The files an installed web app is opened with: `launchQueue`.
///
/// `dartvel build web` writes `file_handlers` into the manifest from
/// `dartvel.fileAssociations`, so an installed PWA is offered for those
/// types. The browser delivers what was opened to the consumer set here, as
/// file handles, once per launch; each is read into memory and handed to
/// `DV.Platform.associations.opened` with its bytes, because a browser file
/// has no path. A tab that is not an installed app, or a browser without
/// file handling (Firefox, Safari), never calls the consumer, and the
/// picker is the way in there.
library dartvel_flutter.platform.web.launch_queue;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../opened_files.dart';
import 'web_interop.dart';

class DVWebLaunchQueue {
  const DVWebLaunchQueue._();

  /// Whether this browser has file handling at all.
  static bool get available => dvJsObject(globalContext, 'launchQueue') != null;

  /// Starts receiving. Set once, at start: the browser keeps the launch until
  /// a consumer is set, so a late consumer still gets the cold start.
  static void register() {
    final JSObject? queue = dvJsObject(globalContext, 'launchQueue');
    if (queue == null) return;
    queue.callMethod<JSAny?>(
      'setConsumer'.toJS,
      ((JSObject params) {
        unawaited(_receive(params));
      }).toJS,
    );
  }

  static Future<void> _receive(JSObject params) async {
    final JSAny? handles = params.getProperty<JSAny?>('files'.toJS);
    if (handles == null || !handles.isA<JSArray>()) return;
    final List<DVOpenedFile> files = <DVOpenedFile>[];
    for (final JSAny? handle in (handles as JSArray<JSAny?>).toDart) {
      if (handle == null || !handle.isA<JSObject>()) continue;
      try {
        final JSAny? file = await dvJsCall(handle as JSObject, 'getFile');
        if (file == null || !file.isA<web.File>()) continue;
        final web.File opened = file as web.File;
        final JSArrayBuffer buffer = await opened.arrayBuffer().toDart;
        files.add(DVOpenedFile(
          name: opened.name,
          mimeType: opened.type.isEmpty ? null : opened.type,
          size: opened.size,
          bytes: buffer.toDart.asUint8List(),
        ));
      } on Object {
        // A handle the browser no longer lets this page read. The others
        // still arrive.
      }
    }
    DVOpenedFiles.deliver(files);
  }
}
