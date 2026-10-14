import 'dart:convert';

import 'asset_source.dart';

/// The route manifest under [webRoot], or null when there is none.
///
/// Read through the source registered for the root, as the server reads the
/// manifest it renders pages from: a web-server binary's site is the pack
/// inside it, and there is no directory on disk to read. Reading the file
/// from disk found nothing in every deployed binary, so every page-reading
/// backend -- the site search first -- saw a site with no pages.
Future<String?> dvReadSiteManifest(String webRoot) async {
  final DVAssetFile? file =
      DVAssetSources.at(webRoot).file('dartvel_routes.json');
  if (file == null) return null;
  return utf8.decode(file.bytes(), allowMalformed: true);
}
