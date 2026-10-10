import 'dart:io' show Platform;

import 'package:dartvel_core/dartvel.dart';

import 'play_billing_jni.dart';
import 'storekit_ffi.dart';

/// StoreKit 2 on iOS and macOS, Play Billing on Android, nothing elsewhere.
DVStoreClient? dvPlatformStoreClient(DVPurchaseChannel channel) {
  final String os = Platform.operatingSystem;
  if (channel == DVPurchaseChannel.appStore &&
      (os == 'ios' || os == 'macos')) {
    return DVStoreKitClient();
  }
  if (channel == DVPurchaseChannel.play && os == 'android') {
    return DVPlayBillingClient();
  }
  return null;
}
