// Play Billing reaches a Dartvel application through Java the build writes
// and one Gradle dependency the build adds. Both are silent when wrong: a
// bridge left out of the APK looks exactly like an application built with
// plain `flutter build`, a dependency added twice is a duplicate-class build
// failure on the second build, and one left behind after `dartvel.purchases`
// was removed ships a billing library the store listing never declared.
import 'package:dartvel_cli/src/build/android_billing_bridge.dart';
import 'package:dartvel_core/dartvel.dart'
    show dvAndroidBillingBridgeClass, dvAndroidBillingLibrary;
import 'package:test/test.dart';

const String groovy = '''
plugins {
    id "com.android.application"
    id "dev.flutter.flutter-gradle-plugin"
}

android {
    namespace "com.example.app"
}

flutter {
    source "../.."
}
''';

const String kotlin = '''
plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.app"
}

flutter {
    source = "../.."
}
''';

void main() {
  group('dartvel.purchases', () {
    test('is declared by a map or by true', () {
      expect(dvPurchasesDeclared(<String, Object?>{'purchases': <String, Object?>{}}),
          isTrue);
      expect(dvPurchasesDeclared(<String, Object?>{'purchases': true}), isTrue);
      expect(
          dvPurchasesDeclared(<String, Object?>{
            'purchases': <String, Object?>{'policy': 'DVPlayStorePolicy'}
          }),
          isTrue);
    });

    test('is not declared when absent, null or false', () {
      expect(dvPurchasesDeclared(const <String, Object?>{}), isFalse);
      expect(dvPurchasesDeclared(<String, Object?>{'purchases': false}), isFalse);
      expect(dvPurchasesDeclared(<String, Object?>{'purchases': null}), isFalse);
      expect(dvPurchasesDeclared(null), isFalse);
    });
  });

  group('the Gradle dependency', () {
    test('is added once to a Groovy build, however often it runs', () {
      final String once = dvAndroidGradleWithBilling(groovy,
          include: true, kotlinScript: false);
      final String twice = dvAndroidGradleWithBilling(once,
          include: true, kotlinScript: false);
      expect(twice, once);
      expect(
          RegExp(RegExp.escape(dvAndroidBillingLibrary)).allMatches(once),
          hasLength(1));
      expect(once, contains('implementation "$dvAndroidBillingLibrary"'));
    });

    test('uses Kotlin script syntax in build.gradle.kts', () {
      final String once =
          dvAndroidGradleWithBilling(kotlin, include: true, kotlinScript: true);
      expect(once, contains('implementation("$dvAndroidBillingLibrary")'));
      expect(dvAndroidGradleWithBilling(once, include: true, kotlinScript: true),
          once);
    });

    test('is taken back out exactly, leaving the file as it was', () {
      for (final (String source, bool kts) in <(String, bool)>[
        (groovy, false),
        (kotlin, true),
      ]) {
        final String added =
            dvAndroidGradleWithBilling(source, include: true, kotlinScript: kts);
        expect(
            dvAndroidGradleWithBilling(added, include: false, kotlinScript: kts),
            source);
      }
    });

    test('a project that never declared purchases is left untouched', () {
      expect(dvAndroidGradleWithBilling(groovy, include: false, kotlinScript: false),
          groovy);
    });
  });

  group('the bridge', () {
    final String java = dvAndroidBillingBridgeSource();

    test('is the class the Dart client looks up', () {
      expect(dvAndroidBillingBridgePath,
          'android/app/src/main/java/$dvAndroidBillingBridgeClass.java');
      expect(java, contains('package dev.dartvel.jni;'));
      expect(java, contains('public final class DartvelBilling'));
    });

    test('exposes start, poll and drainUpdates as the client calls them', () {
      expect(java, contains('public static String start(String request)'));
      expect(java, contains('public static String poll(String id)'));
      expect(java, contains('public static String drainUpdates()'));
    });

    test('is written against Play Billing 8 and later', () {
      // The no-argument enablePendingPurchases() was removed in 8.0, and the
      // product details listener takes a QueryProductDetailsResult.
      expect(java, isNot(contains('enablePendingPurchases()')));
      expect(java, contains('PendingPurchasesParams.newBuilder()'));
      expect(java, contains('.enableOneTimeProducts()'));
      expect(java, contains('.enablePrepaidPlans()'));
      expect(java, contains('enableAutoServiceReconnection()'));
      expect(java, contains('QueryProductDetailsResult'));
      expect(java, isNot(contains('querySkuDetailsAsync')));
    });

    test('opens the sheet on the resumed Activity with the account token', () {
      expect(java, contains('DartvelContext.activity()'));
      expect(java, contains('launchBillingFlow('));
      expect(java, contains('setObfuscatedAccountId('));
      expect(java, contains('setOfferToken('));
    });

    test('consumes consumables and leaves acknowledgement to the server', () {
      expect(java, contains('consumeAsync('));
      // Acknowledging on the device would tell Play the purchase was granted
      // before the server had verified it, and a refused receipt would then
      // never be refunded.
      expect(java, isNot(contains('acknowledgePurchase(')));
    });

    test('reads both subscriptions and one-time products when restoring', () {
      expect(java, contains('BillingClient.ProductType.SUBS'));
      expect(java, contains('BillingClient.ProductType.INAPP'));
      expect(java, contains('queryPurchasesAsync('));
    });

    test('writes the receipt the server adapter reads', () {
      for (final String key in <String>[
        '"purchaseToken"',
        '"productId"',
        '"type"',
        '"orderId"',
      ]) {
        expect(java, contains(key));
      }
    });
  });
}
