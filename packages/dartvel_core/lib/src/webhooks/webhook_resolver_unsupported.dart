/// Where there is no `dart:io`, nothing resolves.
///
/// Webhooks are sent by the application's server. A build without `dart:io`
/// has no business delivering them, and an endpoint whose address cannot be
/// checked is refused rather than trusted.
library dartvel_core.webhooks.resolver_unsupported;

Future<List<String>> dvWebhookResolveHost(String host) async =>
    const <String>[];
