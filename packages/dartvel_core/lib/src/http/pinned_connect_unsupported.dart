/// Where there is no `dart:io`, a request cannot be pinned to an address.
///
/// A browser resolves names itself and offers no way to choose the address,
/// so a pinned request is refused rather than sent unpinned: the pin exists
/// because the unpinned connection is the one that may not be made.
library dartvel_core.http.pinned_connect_unsupported;

import 'transport.dart';

Future<DVHttpStreamedResponse> dvPinnedStreamHttpRequest(
  DVHttpRequest request, {
  Object? context,
}) =>
    Future<DVHttpStreamedResponse>.error(UnsupportedError(
        'A request pinned to ${request.connectAddress} cannot be sent here: '
        'this platform resolves ${request.url.host} itself.'));
