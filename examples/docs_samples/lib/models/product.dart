import 'package:dartvel_core/dartvel.dart';

// docs:start models-paths-resolver
@DVModel(publicPathsResolver: productPaths)
class const _Product({
  required final String slug,
  required final String name,
  required final bool published,
});

// Public, top level, and in the model's own file.
Future<List<String>> productPaths() async => <String>['starter-kit', 'pro-kit'];
// docs:end
