// StoreKit 2 for DV.Purchases on iOS and macOS.
//
// StoreKit 2 is Swift-only and async: there is no Objective-C class behind
// `Product` or `Transaction` for Dart to message, so `dartvel build` writes a
// small @objc class into Runner and compiles it into the application. These
// cover the shim's source, the Xcode wiring that makes it part of the binary,
// and the declaration that decides whether a project gets it at all.
//
// The silent failures: a Swift file left out of the Sources phase builds and
// is never compiled, so objc_getClass answers nil and every purchase button
// reports "no store"; a file left behind after `dartvel.purchases` is removed
// keeps StoreKit linked into an application that sells nothing; and a splice
// that does not strip to the byte puts a diff on every checked-in pbxproj.
import 'dart:io';

import 'package:dartvel_cli/src/build/apple_storekit.dart';
import 'package:dartvel_cli/src/build/apple_widget_reload.dart';
import 'package:dartvel_core/src/purchases/storekit_names.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _pbxproj = '''
// !\$*UTF8*\$!
{
	archiveVersion = 1;
	objects = {

/* Begin PBXBuildFile section */
		97C146FB1CF9000F007C117D /* Main.storyboard in Resources */ = {isa = PBXBuildFile; fileRef = 97C146FA1CF9000F007C117D /* Main.storyboard */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		97C146EE1CF9000F007C117D /* Runner.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Runner.app; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXGroup section */
		97C146F01CF9000F007C117D /* Runner */ = {
			isa = PBXGroup;
			children = (
				97C147021CF9000F007C117D /* Info.plist */,
			);
			path = Runner;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		97C146ED1CF9000F007C117D /* Runner */ = {
			isa = PBXNativeTarget;
			buildPhases = (
				97C146EA1CF9000F007C117D /* Sources */,
			);
			name = Runner;
			productName = Runner;
			productReference = 97C146EE1CF9000F007C117D /* Runner.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXSourcesBuildPhase section */
		97C146EA1CF9000F007C117D /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				74858FAF1ED2DC5600515810 /* AppDelegate.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */
	};
	rootObject = 97C146E61CF9000F007C117D /* Project object */;
}
''';

void main() {
  group('the Swift shim', () {
    final String source = dvAppleStoreKitSource();

    test('is the class the Dart client messages, under its exact name', () {
      expect(source, contains('@objc($dvStoreKitClass)'));
      expect(source, contains('final class $dvStoreKitClass: NSObject'));
    });

    test('exposes the selectors the Dart client sends', () {
      // `start(_:)` is `start:` to the Objective-C runtime, and so on: a
      // mismatch is a selector the class does not answer, which is a crash.
      expect(dvStoreKitStartSelector, 'start:');
      expect(source, contains('@objc public static func start(_ request: NSString) -> NSString'));
      expect(dvStoreKitPollSelector, 'poll:');
      expect(source, contains('@objc public static func poll(_ id: NSString) -> NSString?'));
      expect(source, contains('@objc public static func $dvStoreKitDrainSelector() -> NSString'));
      expect(source, contains('@objc public static func $dvStoreKitListenSelector()'));
    });

    test('uses StoreKit 2 for every operation', () {
      for (final String call in <String>[
        'AppStore.canMakePayments',
        'Product.products(for:',
        'product.purchase(options:',
        '.appAccountToken(',
        '.promotionalOffer(offerID:',
        '.winBackOffer(',
        'Transaction.updates',
        'Transaction.currentEntitlements',
        'Transaction.unfinished',
        'AppStore.sync()',
        '.finish()',
        'jwsRepresentation',
        'isEligibleForIntroOffer',
      ]) {
        expect(source, contains(call), reason: call);
      }
    });

    test('keeps an unverified transaction for the server to judge', () {
      // A device that dropped what StoreKit could not verify would be a
      // client-side receipt check: the one thing the server half refuses to
      // trust. The server verifies the JWS either way.
      expect(source, contains('case .unverified('));
    });

    test('guards StoreKit 2 for deployment targets below iOS 15', () {
      expect(source, contains('#available(iOS 15.0, macOS 12.0'));
      expect(source, contains('StoreKit 2 needs iOS 15 or macOS 12'));
      expect(source, contains('#available(iOS 18.0, macOS 15.0'),
          reason: 'win-back offers are iOS 18');
    });

    test('reports a price as exact milliunits, never a rounded double', () {
      expect(source, contains('NSDecimalNumber(decimal:'));
      expect(source, contains('priceMilliunits'));
      expect(source, isNot(contains('doubleValue')));
    });
  });

  group('the Xcode wiring', () {
    test('compiles the shim into the application target', () {
      final String after =
          dvApplePbxprojWithStoreKit(_pbxproj, include: true);
      expect(after, contains('$dvAppleStoreKitFileName in Sources'));
      expect(
          RegExp('$dvAppleStoreKitIdPrefix\\d+ /\\* $dvAppleStoreKitFileName in Sources \\*/,')
              .hasMatch(after),
          isTrue);
    });

    test('is idempotent and strips back to the byte', () {
      final String once = dvApplePbxprojWithStoreKit(_pbxproj, include: true);
      final String twice = dvApplePbxprojWithStoreKit(once, include: true);
      expect(twice, once);
      expect(dvApplePbxprojWithStoreKit(once, include: false), _pbxproj);
    });

    test('coexists with the widget reload shim, each removable alone', () {
      final String both = dvApplePbxprojWithWidgetReload(
          dvApplePbxprojWithStoreKit(_pbxproj, include: true),
          hasWidgets: true,
          platform: 'ios');
      expect(both, contains(dvAppleStoreKitFileName));
      expect(both, contains(dvAppleWidgetReloadFileName));
      final String storeKitOnly = dvApplePbxprojWithWidgetReload(both,
          hasWidgets: false, platform: 'ios');
      expect(storeKitOnly, dvApplePbxprojWithStoreKit(_pbxproj, include: true));
      expect(dvApplePbxprojWithStoreKit(storeKitOnly, include: false), _pbxproj);
    });

    test('has a prefix of its own', () {
      expect(dvAppleStoreKitIdPrefix, isNot(dvAppleWidgetReloadIdPrefix));
      expect(dvAppleStoreKitIdPrefix, matches(RegExp(r'^[0-9A-F]{12}$')));
    });
  });

  group('dartvel.purchases decides', () {
    test('a map or true declares purchases; absent or false does not', () {
      expect(dvPurchasesDeclared(<Object?, Object?>{'purchases': <Object?, Object?>{}}), isTrue);
      expect(dvPurchasesDeclared(<Object?, Object?>{'purchases': true}), isTrue);
      expect(dvPurchasesDeclared(<Object?, Object?>{'purchases': false}), isFalse);
      expect(dvPurchasesDeclared(<Object?, Object?>{}), isFalse);
      expect(dvPurchasesDeclared(null), isFalse);
    });

    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('dv_storekit_');
      final Directory xcode =
          Directory(p.join(root.path, 'ios', 'Runner.xcodeproj'))
            ..createSync(recursive: true);
      File(p.join(xcode.path, 'project.pbxproj')).writeAsStringSync(_pbxproj);
      Directory(p.join(root.path, 'ios', 'Runner')).createSync();
    });
    tearDown(() => root.deleteSync(recursive: true));

    File shim() =>
        File(p.join(root.path, 'ios', 'Runner', dvAppleStoreKitFileName));
    String pbxproj() => File(p.join(
            root.path, 'ios', 'Runner.xcodeproj', 'project.pbxproj'))
        .readAsStringSync();

    test('a declaring project gets the shim, compiled in', () {
      final bool wrote = dvWriteAppleStoreKit(root.path, 'ios',
          <Object?, Object?>{'purchases': <Object?, Object?>{}});
      expect(wrote, isTrue);
      expect(shim().readAsStringSync(), dvAppleStoreKitSource());
      expect(pbxproj(), contains(dvAppleStoreKitFileName));
    });

    test('removing the declaration takes the shim and its wiring out', () {
      dvWriteAppleStoreKit(root.path, 'ios',
          <Object?, Object?>{'purchases': true});
      final bool wrote =
          dvWriteAppleStoreKit(root.path, 'ios', <Object?, Object?>{});
      expect(wrote, isFalse);
      expect(shim().existsSync(), isFalse);
      expect(pbxproj(), _pbxproj);
    });

    test('a project that never declared purchases is left untouched', () {
      dvWriteAppleStoreKit(root.path, 'ios', <Object?, Object?>{});
      expect(shim().existsSync(), isFalse);
      expect(pbxproj(), _pbxproj);
    });
  });
}
