import 'package:dartvel_core/dartvel.dart';

/// A coffee the roastery sells.
///
/// One declaration gives the shop its catalogue: the generated `Product.Form`,
/// `Product.Table` and `Product.Admin` are what the Manage screen is made of,
/// `Product.watch` keeps the shop grid current, and the backend's catalogue
/// function reads the same table on the server.
///
/// Static paths come from an explicit resolver rather than from enumerating
/// published records (`_User` shows that common case): when the set to
/// generate is a subset, `publicPathsResolver:` names the function that
/// decides. The route is still the model's own, so it is never written out as
/// a string here.
///
/// Billable, so the generator has a billable model to emit and a compiler has
/// one to read: the declared price is the Coffee Club subscription, in the
/// project's dartvel.nativeCurrency. A model declaring one without that
/// setting fails the build, because a hundred of a guessed currency is a
/// plausible number nothing catches.
@DVModel(publicPathsResolver: productPaths, billable: true, nativePrice: 2499)
@pragma('vm:entry-point')
class _Product {
  final String slug;
  final String name;

  /// Where it was grown, as the bag says it: "Huila, Colombia".
  final String origin;

  /// light, medium or dark.
  final String roast;

  /// What it tastes like, comma separated.
  final String notes;
  final String description;

  /// The price of one bag, in cents of the native currency.
  final int priceCents;
  final int weightGrams;
  final bool published;

  const _Product({
    required this.slug,
    required this.name,
    required this.origin,
    required this.roast,
    required this.notes,
    required this.description,
    required this.priceCents,
    required this.weightGrams,
    required this.published,
  });
}

/// The slugs static generation should render: the coffees on the shelf this
/// week, not every one the roastery has ever sold.
Future<List<String>> productPaths() async => <String>['huila', 'yirgacheffe'];
