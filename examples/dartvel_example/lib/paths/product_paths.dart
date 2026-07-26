// ignore_for_file: unused_element

import 'package:dartvel_core/dartvel.dart';

/// Supplies the slugs static generation should render for a parameterized
/// product route. Static routes are generated automatically; a parameterized
/// one needs its values enumerated.
@DVStaticPaths(route: '/products/:slug')
Future<List<String>> productPaths() async {
  return <String>['starter-kit', 'pro-kit'];
}
