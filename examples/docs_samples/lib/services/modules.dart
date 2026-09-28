import '../dartvel_client/dartvel_client.dart';

// docs:start modules-dart-package
// dartvel add pub:slugify wrote modules/dv_slugify_module, and the
// parent calls it through the one surface it already has.
Future<void> publish(Article article) async {
  final String slug = DV.Modules.slugify.slugify(article.title);
  await article.copyWith(slug: slug).save();
}
// docs:end
