/// Wires `DV.Purchases` on a device to the running platform.
///
/// The core half knows nothing about Flutter, so it asks for a store client,
/// a backend and a channel through resolvers. This fills them in: StoreKit 2
/// on iOS and macOS, Play Billing on Android, the signed-in session for the
/// backend, and the build's channel. Each is consulted the first time a
/// purchase needs it, never at import.
library dartvel_flutter.purchases.runtime;

import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../auth/session_client.dart';
import 'open_url.dart';
import 'store_clients.dart';

/// The channel this build sells from.
///
/// `--dart-define=DARTVEL_PURCHASE_CHANNEL=desktop` overrides it, for a macOS
/// build distributed outside the Mac App Store, where StoreKit cannot sell.
DVPurchaseChannel dvPurchaseChannel() {
  const String declared = String.fromEnvironment('DARTVEL_PURCHASE_CHANNEL');
  final DVPurchaseChannel? named =
      DVPurchaseChannel.values.asNameMap()[declared];
  if (named != null) return named;
  if (kIsWeb) return DVPurchaseChannel.web;
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => DVPurchaseChannel.appStore,
    TargetPlatform.android => DVPurchaseChannel.play,
    _ => DVPurchaseChannel.desktop,
  };
}

bool _installed = false;

/// Installs the resolvers, once. Called by the `DV.Purchases` getter.
void dvInstallPurchaseRuntime() {
  if (_installed) return;
  _installed = true;
  DVPurchaseDevice.channelResolver ??= dvPurchaseChannel;
  DVPurchaseDevice.storeResolver ??= dvPlatformStoreClient;
  DVPurchaseDevice.urlOpener ??= dvExternalUrlOpener();
  DVPurchaseDevice.backendResolver ??= () {
    final DVSessionClient? session = DVSessionClient.installed;
    if (session == null) return null;
    return DVHttpPurchaseBackend(
        (String method, String path, Map<String, Object?>? body) async {
      final DVHttpResponse response =
          await session.send(method, path, body: body);
      return (response.statusCode, response.body);
    });
  };
}

/// `DV.Purchases.watch(context, entitlement)`: whether the signed-in person
/// holds [entitlement], rebuilding the widget when that changes -- a
/// purchase completing, an Ask to Buy approved a day later, a refund
/// arriving at the next sync.
extension DVPurchasesWatch on DVPurchases {
  bool watch(BuildContext context, Entitlement entitlement) {
    final Element element = context as Element;
    if (_watchers[element] == null) {
      late final StreamSubscription<void> subscription;
      subscription = entitlementChanges.listen((_) {
        if (element.mounted) {
          element.markNeedsBuild();
          return;
        }
        _watchers[element] = null;
        unawaited(subscription.cancel());
      });
      _watchers[element] = subscription;
    }
    return holds(entitlement);
  }
}

final Expando<StreamSubscription<void>> _watchers =
    Expando<StreamSubscription<void>>('DV.Purchases.watch');
