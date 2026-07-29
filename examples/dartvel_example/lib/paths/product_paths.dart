import 'package:dartvel_core/dartvel.dart';

/// Supplies the slugs static generation should render for a parameterized
/// product route. Static routes are generated automatically; a parameterized
/// one needs its values enumerated.
@DVStaticPaths(route: '/products/:slug')
@pragma('vm:entry-point')
Future<List<String>> _productPaths() async => productPaths();

Future<List<String>> productPaths() async {
  return <String>['starter-kit', 'pro-kit'];
}
