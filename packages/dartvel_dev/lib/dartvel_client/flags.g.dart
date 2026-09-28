// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: unused_import, unnecessary_import

import 'package:dartvel_core/dartvel.dart';

/// The flags this build declares, generated from `@DVFlags()`.
///
/// Read `Flags.name.value` anywhere, or `context.flag(Flags.name)`
/// in a build method to rebuild when the rules change.
abstract final class Flags {
  /// Every flag above, so the runtime can notice a rule set naming one this
  /// build does not declare, and `dartvel flags prune` can list what is due.
  static final List<DVFeatureFlag<Object?>> all = <DVFeatureFlag<Object?>>[];
}

/// Declares this build's flags to the runtime.
void registerDartvelFlags() {
  DVFlags.declare(Flags.all);
}
