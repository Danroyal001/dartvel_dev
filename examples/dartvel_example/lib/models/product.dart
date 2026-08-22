import 'package:dartvel_core/dartvel.dart';

/// A model whose static paths come from an explicit resolver rather than from
/// enumerating published records.
///
/// `_User` shows the common case, `generatePublicPages: true`, where static
/// generation renders one page per published record. This shows the other one:
/// when the set to generate is a subset, a particular order, or drawn from
/// somewhere the model does not know about, `publicPathsResolver:` names the
/// function that decides.
///
/// The route is still the model's own, so it is never written out as a string
/// here — a route repeated in an annotation drifts silently the moment the page
/// file moves.
@DVModel(publicPathsResolver: productPaths)
@pragma('vm:entry-point')
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

/// The slugs static generation should render.
///
/// A real application would query here. This one returns a fixed pair so the
/// example builds without a database.
Future<List<String>> productPaths() async => <String>[
      'starter-kit',
      'pro-kit',
    ];
