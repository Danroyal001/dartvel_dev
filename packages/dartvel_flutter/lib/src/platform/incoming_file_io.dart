/// Reading a dropped file by its path, where there is a filesystem.
library;

import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> dvReadLocalFile(String path) => File(path).readAsBytes();
