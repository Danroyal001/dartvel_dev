import 'dart:io';

import 'target.dart';

/// The target `dart:io` reports.
DVMemoryTarget dvDetectMemoryTarget() => switch (Platform.operatingSystem) {
  'android' => DVMemoryTarget.android,
  'ios' => DVMemoryTarget.ios,
  'windows' => DVMemoryTarget.windows,
  'macos' => DVMemoryTarget.macos,
  'fuchsia' => DVMemoryTarget.fuchsia,
  _ => DVMemoryTarget.linux,
};
