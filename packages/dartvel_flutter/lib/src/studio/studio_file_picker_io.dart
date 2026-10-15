/// Picking files where there is a filesystem: the platform's open dialog,
/// and the files read from the paths it returns.
library;

import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show dvStudioMediaTypes;

import '../platform/dialogs.dart';
import 'studio_file_picker.dart' show DVStudioPickedFile;

Future<List<DVStudioPickedFile>> dvPickFiles() async {
  final List<String> paths = await const DVDialogs().openFile(
    title: 'Upload to the media library',
    multiple: true,
    filters: <DVFileFilter>[
      DVFileFilter(
        label: 'Media',
        extensions: dvStudioMediaTypes.keys.toList(),
      ),
    ],
  );
  return <DVStudioPickedFile>[
    for (final String path in paths)
      (
        name: path.split(Platform.pathSeparator).last,
        bytes: await File(path).readAsBytes(),
      ),
  ];
}
