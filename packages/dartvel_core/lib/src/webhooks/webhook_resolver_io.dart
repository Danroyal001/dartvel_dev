/// Resolves a webhook endpoint's host where `dart:io` is available.
library dartvel_core.webhooks.resolver_io;

import 'dart:io';

/// Every address [host] resolves to, or none when it does not resolve.
///
/// All of them rather than the first, because an endpoint is refused when any
/// address is private: a name with one public and one loopback record is a
/// coin toss over which the connection reaches.
Future<List<String>> dvWebhookResolveHost(String host) async {
  try {
    final List<InternetAddress> addresses = await InternetAddress.lookup(host);
    return <String>[
      for (final InternetAddress address in addresses) address.address,
    ];
  } on SocketException {
    return const <String>[];
  }
}
