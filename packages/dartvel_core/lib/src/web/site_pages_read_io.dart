import 'dart:io';

/// The route manifest under [webRoot], or null when there is none.
Future<String?> dvReadSiteManifest(String webRoot) async {
  final File file = File('$webRoot${Platform.pathSeparator}dartvel_routes.json');
  if (!await file.exists()) return null;
  return file.readAsString();
}
