import 'dart:io' show Platform;

// dartvel_core has its own Platform enum (build targets), which would hide
// dart:io's and leave Platform.operatingSystem unresolved.
import 'package:dartvel_core/dartvel.dart' hide Platform;

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
