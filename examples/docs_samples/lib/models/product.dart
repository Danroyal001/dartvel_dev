import 'package:dartvel_core/dartvel.dart';

// docs:start models-paths-resolver
@DVModel(publicPathsResolver: productPaths)
class _Product {
  final String slug;
  final String name;
  final bool published;

  const _Product({
    required this.slug,
    required this.name,
    required this.published,
  });
}

// Public, top level, and in the model's own file.
Future<List<String>> productPaths() async => <String>['starter-kit', 'pro-kit'];
// docs:end
