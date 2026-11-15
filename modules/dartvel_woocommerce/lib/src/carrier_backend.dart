import 'runtime.dart';

/// Runs the operation named [operation] with the JSON [arguments] a client
/// sent, answering with JSON. Served by the application's backend at
/// `<apiBasePath>/_dv/modules/<id>/<operation>`.
///
/// Four operations are carried here, the ones a storefront needs:
/// `products`, `product`, `startCheckout` and `orderStatus`. Anything else
/// is refused rather than run.
Future<Object?> dvModuleDispatch(
  String operation,
  Map<String, Object?> arguments,
) =>
    WooCommerceRuntime.instance.dispatch(operation, arguments);
