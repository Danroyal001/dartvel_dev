import 'package:dartvel_core/dartvel.dart';

/// The web and every target without a store binding: no store client, so a
/// store channel refuses with `DV-PURCHASE-009` and the web goes to the
/// gateway.
DVStoreClient? dvPlatformStoreClient(DVPurchaseChannel channel) => null;
