/// Picking files in a browser: an `<input type="file" multiple>`, read in as
/// bytes, because a browser hands over files, never paths.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:dartvel_core/dartvel.dart' show dvStudioMediaTypes;
import 'package:web/web.dart' as web;

import 'studio_file_picker.dart' show DVStudioPickedFile;

Future<List<DVStudioPickedFile>> dvPickFiles() async {
  final web.HTMLInputElement input =
      web.document.createElement('input') as web.HTMLInputElement;
  input.type = 'file';
  input.multiple = true;
  input.accept = <String>[
    for (final String extension in dvStudioMediaTypes.keys) '.$extension',
  ].join(',');
  input.style.position = 'fixed';
  input.style.left = '-10000px';
  web.document.body?.append(input);
  final Completer<bool> chosen = Completer<bool>();
  input.addEventListener('change', ((web.Event _) {
    if (!chosen.isCompleted) chosen.complete(true);
  }).toJS);
  input.addEventListener('cancel', ((web.Event _) {
    if (!chosen.isCompleted) chosen.complete(false);
  }).toJS);
  input.click();
  try {
    if (!await chosen.future) return const <DVStudioPickedFile>[];
    final web.FileList? files = input.files;
    if (files == null) return const <DVStudioPickedFile>[];
    return <DVStudioPickedFile>[
      for (int index = 0; index < files.length; index++)
        (
          name: files.item(index)!.name,
          bytes: (await files.item(index)!.arrayBuffer().toDart)
              .toDart
              .asUint8List(),
        ),
    ];
  } finally {
    input.remove();
  }
}
