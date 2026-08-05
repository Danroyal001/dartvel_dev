import 'dart:io';

import 'package:flutter/widgets.dart';

ImageProvider<Object>? fileImageProvider(String path) => FileImage(File(path));
