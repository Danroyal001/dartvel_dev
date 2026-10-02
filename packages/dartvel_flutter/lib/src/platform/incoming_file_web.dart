/// A browser has no filesystem path to read; a dropped file carries its own
/// reader instead, so reaching here means a path was given where none exists.
library;

import 'dart:typed_data';

Future<Uint8List> dvReadLocalFile(String path) =>
    Future<Uint8List>.error(UnsupportedError('A browser cannot read "$path" by path.'));
