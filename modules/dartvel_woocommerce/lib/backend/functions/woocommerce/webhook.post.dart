import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_woocommerce/src/runtime.dart';

/// Where the store says an order changed: `POST /_dartvel/woocommerce/webhook`
/// on the application's backend, outside the API base path.
///
/// Save a webhook in the store (WooCommerce > Settings > Advanced >
/// Webhooks) with the topic *Order updated*, this address as its delivery
/// URL, and a secret; put the same secret in the server's environment as
/// `WOOCOMMERCE_WEBHOOK_SECRET`.
@DVBackendFunction(rawPath: '/_dartvel/woocommerce/webhook')
Future<Response> wooCommerceWebhook(Request request) =>
    WooCommerceRuntime.instance.webhook.handle(request);
