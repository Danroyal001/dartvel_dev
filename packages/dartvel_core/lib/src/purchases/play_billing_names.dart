/// Names the Play Billing bridge is reached by, shared by the build that
/// writes it and the Dart client that calls it.
///
/// One constant each, because the two halves live in different packages and
/// a name spelled twice is a lookup that fails for ever -- and fails the same
/// way an APK built with plain `flutter build` does, so nothing could tell
/// the two apart.
library dartvel.purchases.play_billing_names;

/// The generated Java class, in JNI's slash form.
const String dvAndroidBillingBridgeClass = 'dev/dartvel/jni/DartvelBilling';

/// The Play Billing Library the generated project depends on.
///
/// 9.1.0 is the newest on Google Maven as of 2026-10-09. 8.0 changed
/// `queryProductDetailsAsync`'s listener to `(BillingResult,
/// QueryProductDetailsResult)` and removed the no-argument
/// `enablePendingPurchases()`; the bridge is written against that shape.
const String dvAndroidBillingLibrary = 'com.android.billingclient:billing:9.1.0';

