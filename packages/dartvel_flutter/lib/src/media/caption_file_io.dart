import 'dart:io';

Future<String> dvReadCaptionFile(String path) => File(path).readAsString();
