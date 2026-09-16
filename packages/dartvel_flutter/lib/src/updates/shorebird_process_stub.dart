import 'shorebird_updates.dart';

/// No FFI on this platform, so no updater.
DVShorebirdNative dvShorebirdProcessUpdater() => const _Absent();

class _Absent implements DVShorebirdNative {
  const _Absent();
  @override
  bool get linked => false;
  @override
  int currentPatch() => 0;
  @override
  int nextPatch() => 0;
  @override
  bool checkForUpdate(String? channel) => false;
  @override
  (int, String?) update(String? channel) => (DVShorebirdNative.error, null);
}
