import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';

/// A real policy, so the generated registrations are read by a compiler.
///
/// The generator emits a registration per conventional method and tears the
/// method off rather than wrapping it, which is what makes the registry key
/// the type the policy actually takes. Nothing about that is visible in a
/// test asserting on the generated string: it would pass just as well for
/// source that does not compile. An example the build compiles is the only
/// check that catches that, and it is the same reason the example configures
/// a real CORS policy and a real native price.
@DVPolicy(Product)
class ProductPolicy {
  /// Anybody may look at a published product; an unpublished one is for the
  /// people who can publish.
  bool view(User user, Product product) => product.published || user.published;

  bool update(User user, Product product) => user.published;
}
