// The generated model factories, as the testing docs page shows them.
import 'package:docs_samples/dartvel_client/dartvel_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // docs:start testing-factories
  setUp(ProductFactory.resetSequence);

  test('each product the factory makes is its own record', () {
    final List<Product> products =
        const ProductFactory(published: false).createMany(3);

    expect(products.map((Product p) => p.slug).toSet(), hasLength(3));
    expect(products.every((Product p) => !p.published), isTrue);
  });
  // docs:end
}
