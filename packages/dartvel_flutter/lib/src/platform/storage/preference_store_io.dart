import 'device_storage.dart';
import 'preference_store.dart';

/// The app's storage directory, as DV.Platform.fileStorage has it.
DVPreferenceStore dvPlatformPreferenceStore() {
  final String? directory = DVDeviceStorage.instance.directory;
  return directory == null ? DVMemoryPreferenceStore() : DVFilePreferenceStore('$directory/preferences');
}
