// The Xcode target that builds the widget extension.
//
// Generating the Swift, the Info.plist and the entitlements is the easy
// half. None of it is built by anything until the Xcode project has a target
// for it, and that target has to be spliced into project.pbxproj -- a file
// Xcode wrote and a build tool is normally told to leave alone.
//
// The failure modes are all silent in the same way. A pbxproj that Xcode
// cannot parse is a project that will not open, which is loud. Everything
// short of that is quiet: an extension with no embed phase builds and is not
// in the app; a target absent from the project's target list is never built
// at all; a second build that appends rather than replaces gives Xcode two
// targets with one name.
import 'package:dartvel_cli/src/build/apple_widget_target.dart';
import 'package:test/test.dart';

/// The shape `flutter create` writes, cut to the parts the splice anchors
/// on. Real ids, because the splice finds the main group and the products
/// group by reading the project rather than by knowing Flutter's numbers.
const String _pbxproj = '''
// !\$*UTF8*\$!
{
	archiveVersion = 1;
	objectVersion = 54;
	objects = {

/* Begin PBXBuildFile section */
		97C146FB1CF9000F007C117D /* Main.storyboard in Resources */ = {isa = PBXBuildFile; fileRef = 97C146FA1CF9000F007C117D /* Main.storyboard */; };
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		331C8085294A63A400263BE5 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 97C146E61CF9000F007C117D /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 97C146ED1CF9000F007C117D;
			remoteInfo = Runner;
		};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
		9705A1C41CF9048500538489 /* Embed Frameworks */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 10;
			files = (
			);
			name = "Embed Frameworks";
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
		97C146EE1CF9000F007C117D /* Runner.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Runner.app; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		97C146EB1CF9000F007C117D /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		97C146E51CF9000F007C117D = {
			isa = PBXGroup;
			children = (
				97C146F01CF9000F007C117D /* Runner */,
				97C146EF1CF9000F007C117D /* Products */,
			);
			sourceTree = "<group>";
		};
		97C146EF1CF9000F007C117D /* Products */ = {
			isa = PBXGroup;
			children = (
				97C146EE1CF9000F007C117D /* Runner.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
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
			buildConfigurationList = 97C147051CF9000F007C117D /* Build configuration list for PBXNativeTarget "Runner" */;
			buildPhases = (
				9740EEB61CF901F6004384FC /* Run Script */,
				97C146EA1CF9000F007C117D /* Sources */,
				97C146EB1CF9000F007C117D /* Frameworks */,
				97C146EC1CF9000F007C117D /* Resources */,
				9705A1C41CF9048500538489 /* Embed Frameworks */,
				3B06AD1E1E4923F5004D2608 /* Thin Binary */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = Runner;
			productName = Runner;
			productReference = 97C146EE1CF9000F007C117D /* Runner.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		97C146E61CF9000F007C117D /* Project object */ = {
			isa = PBXProject;
			attributes = {
				LastUpgradeCheck = 1510;
				TargetAttributes = {
					97C146ED1CF9000F007C117D = {
						CreatedOnToolsVersion = 7.3.1;
					};
				};
			};
			buildConfigurationList = 97C146E91CF9000F007C117D /* Build configuration list for PBXProject "Runner" */;
			compatibilityVersion = "Xcode 9.3";
			mainGroup = 97C146E51CF9000F007C117D;
			productRefGroup = 97C146EF1CF9000F007C117D /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				97C146ED1CF9000F007C117D /* Runner */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		97C146EC1CF9000F007C117D /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		97C146EA1CF9000F007C117D /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		331C8086294A63A400263BE5 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = 97C146ED1CF9000F007C117D /* Runner */;
			targetProxy = 331C8085294A63A400263BE5 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		97C147031CF9000F007C117D /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				SDKROOT = iphoneos;
			};
			name = Debug;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		97C147051CF9000F007C117D /* Build configuration list for PBXNativeTarget "Runner" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				97C147031CF9000F007C117D /* Debug */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = 97C146E61CF9000F007C117D /* Project object */;
}
''';

String _spliced({bool widgets = true}) => dvApplePbxprojWithWidgets(
      _pbxproj,
      hasWidgets: widgets,
      bundleId: 'com.example.shop',
      platform: 'ios',
    );

void main() {
  group('the extension target', () {
    test('is in the project\'s target list, or it is never built', () {
      // A PBXNativeTarget that exists as an object and is not in the
      // project's targets is a target Xcode does not know about. Nothing
      // errors; the extension is simply never built, and the app installs
      // without it.
      final String out = _spliced();

      final int targets = out.indexOf('targets = (');
      final int close = out.indexOf(');', targets);
      expect(out.substring(targets, close), contains(dvAppleWidgetTargetId));
    });

    test('is embedded in the application, or it is built and left behind', () {
      // Without a Copy Files phase into the PlugIns folder, the .appex is
      // built into the products directory and never enters the .app. The
      // build succeeds and the widget is not on the device.
      final String out = _spliced();

      expect(out, contains('dstSubfolderSpec = 13'));
      expect(out, contains('Embed App Extensions'));
      // And the phase has to be one of Runner's, not an orphan object.
      final int runner = out.indexOf('97C146ED1CF9000F007C117D /* Runner */ = {');
      final int phases = out.indexOf('buildPhases = (', runner);
      final int phasesEnd = out.indexOf(');', phases);
      expect(out.substring(phases, phasesEnd),
          contains('Embed App Extensions'));
    });

    test('the embed runs before Thin Binary, or Xcode finds a cycle', () {
      // Flutter's Thin Binary script walks the built .app and thins every
      // binary in it, PlugIns included. Embedding the extension after that
      // ran gave Xcode a copy into a bundle the script had already consumed,
      // and it refused the whole build: "Cycle inside Runner; building could
      // produce unreliable results." Embedding first also gets the
      // extension thinned, which is what the script is for.
      final String out = _spliced();

      final int runner =
          out.indexOf('97C146ED1CF9000F007C117D /* Runner */ = {');
      final int phases = out.indexOf('buildPhases = (', runner);
      final int phasesEnd = out.indexOf(');', phases);
      final String list = out.substring(phases, phasesEnd);

      final int embed = list.indexOf('Embed App Extensions');
      final int thin = list.indexOf('Thin Binary');
      expect(embed, greaterThan(-1));
      expect(thin, greaterThan(-1));
      expect(embed, lessThan(thin));
    });

    test('the application waits for it, rather than racing it', () {
      // Without a target dependency, Xcode is free to build the app first
      // and embed an .appex that is not there yet -- which fails on some
      // machines and passes on others, which is worse.
      final String out = _spliced();

      final int runner = out.indexOf('97C146ED1CF9000F007C117D /* Runner */ = {');
      final int deps = out.indexOf('dependencies = (', runner);
      final int depsEnd = out.indexOf(');', deps);
      expect(out.substring(deps, depsEnd), contains('PBXTargetDependency'));
    });

    test('its product is an app extension, not an application', () {
      final String out = _spliced();

      expect(out, contains('com.apple.product-type.app-extension'));
      expect(out, contains('.appex'));
    });

    test('it is signed with the entitlements that carry the App Group', () {
      // An extension built without them reads its own empty container.
      final String out = _spliced();

      expect(out, contains('CODE_SIGN_ENTITLEMENTS'));
      expect(out, contains('group.com.example.shop.dartvelwidgets'));
    });

    test('its bundle id is under the application\'s, as Apple requires', () {
      // An extension whose identifier is not prefixed by the containing
      // app's is rejected at submission, months after it built.
      final String out = _spliced();

      expect(out, contains('com.example.shop.DartvelWidgets'));
    });
  });

  group('rewriting a project that already has it', () {
    test('a second build leaves one target, not two', () {
      // Two targets with one name is a project Xcode opens and cannot
      // build, from a build that succeeded.
      final String once = _spliced();
      final String twice = dvApplePbxprojWithWidgets(once,
          hasWidgets: true, bundleId: 'com.example.shop', platform: 'ios');

      expect('com.apple.product-type.app-extension'.allMatches(twice).length,
          1);
      expect(dvAppleWidgetTargetId.allMatches(twice).length,
          dvAppleWidgetTargetId.allMatches(once).length);
    });

    test('it is byte-identical the second time', () {
      // The pbxproj is checked in. A build that rewrites it differently
      // every time is a diff on every branch and a merge conflict on every
      // pull request.
      final String once = _spliced();
      final String twice = dvApplePbxprojWithWidgets(once,
          hasWidgets: true, bundleId: 'com.example.shop', platform: 'ios');

      expect(twice, once);
    });

    test('taking the widgets away puts the project back as it was', () {
      // A project that stops declaring home widgets must not keep a target
      // pointing at Swift the build no longer writes -- that is a project
      // that will not build, from removing a feature.
      final String out = dvApplePbxprojWithWidgets(_spliced(),
          hasWidgets: false, bundleId: 'com.example.shop', platform: 'ios');

      expect(out, _pbxproj);
    });

    test('a project with no widgets is left exactly as it was', () {
      expect(_spliced(widgets: false), _pbxproj);
    });
  });

  group('the two platforms', () {
    test('macOS embeds into a different folder than iOS', () {
      // On macOS an app extension lives in Contents/PlugIns and the SDK is
      // macosx. Copying the iOS phase across produces a bundle that builds
      // and is refused at launch.
      final String macos = dvApplePbxprojWithWidgets(_pbxproj,
          hasWidgets: true, bundleId: 'com.example.shop', platform: 'macos');

      expect(macos, contains('SDKROOT = macosx'));
      expect(macos, isNot(contains('IPHONEOS_DEPLOYMENT_TARGET')));
    });

    test('iOS says a deployment target and a device family', () {
      // Neither appears in the project this is spliced into, so both are
      // this target's own. A device family of 1,2 is what makes the widget
      // offered on iPad as well as iPhone.
      expect(_spliced(), contains('IPHONEOS_DEPLOYMENT_TARGET'));
      expect(_spliced(), contains('TARGETED_DEVICE_FAMILY'));
      expect(_spliced(), isNot(contains('MACOSX_DEPLOYMENT_TARGET')));
    });
  });

  group('the file it leaves behind', () {
    test('every object it adds is closed', () {
      // The cheapest check that the result is still a plist: braces balance
      // and parentheses balance. A pbxproj that does not parse is a project
      // that will not open, and the message Xcode gives names a line number
      // rather than a cause.
      final String out = _spliced();

      expect('{'.allMatches(out).length, '}'.allMatches(out).length);
      expect('('.allMatches(out).length, ')'.allMatches(out).length);
    });

    test('it does not invent an object id that is already taken', () {
      // Two objects with one id is a project Xcode rewrites into something
      // nobody wrote.
      final String out = _spliced();
      final RegExp id = RegExp(r'^\t\t([0-9A-F]{24}) ', multiLine: true);
      final List<String> ids = id
          .allMatches(out)
          .map((RegExpMatch m) => m.group(1)!)
          .toList();

      expect(ids.toSet().length, ids.length);
    });
  });

  _appSide();
}

// ---------------------------------------------------------------------------
// The application's own half of the App Group.
//
// The extension having the group entitlement is half of it. The application
// has to have it too, or it writes to its own container and the widget --
// correctly entitled, correctly signed -- reads an empty one and renders the
// placeholder forever. Nothing errors at either end.

void _appSide() {
  group('the application\'s entitlements', () {
    test('a project with none gets a file that claims the group', () {
      // A plain Flutter iOS project has no Runner.entitlements at all.
      final String out =
          dvAppleAppEntitlements('', 'group.com.example.shop.dartvelwidgets');

      expect(out, contains('com.apple.security.application-groups'));
      expect(out, contains('group.com.example.shop.dartvelwidgets'));
      expect(out, startsWith('<?xml'));
    });

    test('a project with entitlements keeps the ones it had', () {
      // macOS ships DebugProfile.entitlements with the sandbox and the
      // network client in it. Replacing that file would take away the
      // network from an application that was using it.
      const String existing = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
</dict>
</plist>
''';
      final String out =
          dvAppleAppEntitlements(existing, 'group.com.example.shop.x');

      expect(out, contains('com.apple.security.app-sandbox'));
      expect(out, contains('com.apple.security.network.client'));
      expect(out, contains('group.com.example.shop.x'));
    });

    test('a second build does not claim it twice', () {
      // A duplicate key in an entitlements plist is a signing failure whose
      // message names the file and not the build that wrote it.
      final String once = dvAppleAppEntitlements('', 'group.a.b');
      final String twice = dvAppleAppEntitlements(once, 'group.a.b');

      expect(twice, once);
      expect('group.a.b'.allMatches(twice).length, 1);
    });

    test('a group that changed replaces the one before it', () {
      // A renamed bundle id is a new group, and an application still
      // claiming the old one writes where nothing reads.
      final String once = dvAppleAppEntitlements('', 'group.a.old');
      final String twice = dvAppleAppEntitlements(once, 'group.a.new');

      expect(twice, contains('group.a.new'));
      expect(twice, isNot(contains('group.a.old')));
    });
  });

  group('pointing the application at its entitlements', () {
    test('a target that has none is given them', () {
      final String out = dvApplePbxprojWithAppEntitlements(_pbxproj,
          hasWidgets: true, path: 'Runner/Runner.entitlements');

      expect(out, contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements'));
    });

    test('a target that already has them is left alone', () {
      // macOS projects are already wired to DebugProfile.entitlements, and
      // overwriting that setting takes the sandbox off the application --
      // a build that removes a security boundary to add a widget.
      final String wired = _pbxproj.replaceFirst(
          '\t\t\t\tSDKROOT = iphoneos;',
          '\t\t\t\tCODE_SIGN_ENTITLEMENTS = '
          'Runner/DebugProfile.entitlements;\n\t\t\t\tSDKROOT = iphoneos;');

      expect(
          dvApplePbxprojWithAppEntitlements(wired,
              hasWidgets: true, path: 'Runner/Runner.entitlements'),
          wired);
    });

    test('taking the widgets away takes the setting back out', () {
      final String once = dvApplePbxprojWithAppEntitlements(_pbxproj,
          hasWidgets: true, path: 'Runner/Runner.entitlements');

      expect(
          dvApplePbxprojWithAppEntitlements(once,
              hasWidgets: false, path: 'Runner/Runner.entitlements'),
          _pbxproj);
    });
  });

  group('a project with a test target as well', () {
    // Every project `flutter create` makes has one, and this fixture puts it
    // where Xcode does: the PBXNativeTarget section is sorted by id, and
    // RunnerTests' id sorts first in a real project as often as not.
    //
    // The embed phase and the target dependency go onto the application, and
    // both were reached by finding the application target and then searching
    // forward for a list. With a test target in the way, forward from the
    // wrong place is the test target's list -- so the extension would be
    // built and never embedded, and the .app would install without it. The
    // build succeeds either way.
    const String withTests = '''
// !\$*UTF8*\$!
{
	objects = {

/* Begin PBXBuildFile section */
		97C146FB1CF9000F007C117D /* Main.storyboard in Resources */ = {isa = PBXBuildFile; fileRef = 97C146FA1CF9000F007C117D /* Main.storyboard */; };
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
		97C146EE1CF9000F007C117D /* Runner.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Runner.app; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXGroup section */
		97C146E51CF9000F007C117D = {
			isa = PBXGroup;
			children = (
			);
			sourceTree = "<group>";
		};
		97C146EF1CF9000F007C117D /* Products */ = {
			isa = PBXGroup;
			children = (
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		331C8080294A63A400263BE5 /* RunnerTests */ = {
			isa = PBXNativeTarget;
			buildPhases = (
				331C807D294A63A400263BE5 /* Sources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = RunnerTests;
			productName = RunnerTests;
			productType = "com.apple.product-type.bundle.unit-test";
		};
		97C146ED1CF9000F007C117D /* Runner */ = {
			isa = PBXNativeTarget;
			buildPhases = (
				97C146EA1CF9000F007C117D /* Sources */,
				3B06AD1E1E4923F5004D2608 /* Thin Binary */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = Runner;
			productName = Runner;
			productReference = 97C146EE1CF9000F007C117D /* Runner.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		97C146E61CF9000F007C117D /* Project object */ = {
			isa = PBXProject;
			attributes = {
				TargetAttributes = {
					97C146ED1CF9000F007C117D = {
						CreatedOnToolsVersion = 7.3.1;
					};
				};
			};
			mainGroup = 97C146E51CF9000F007C117D;
			productRefGroup = 97C146EF1CF9000F007C117D /* Products */;
			targets = (
				97C146ED1CF9000F007C117D /* Runner */,
				331C8080294A63A400263BE5 /* RunnerTests */,
			);
		};
/* End PBXProject section */

/* Begin PBXSourcesBuildPhase section */
		331C807D294A63A400263BE5 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			files = (
			);
		};
		97C146EA1CF9000F007C117D /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			files = (
			);
		};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
/* End XCConfigurationList section */
	};
	rootObject = 97C146E61CF9000F007C117D /* Project object */;
}
''';

    String spliced() => dvApplePbxprojWithWidgets(withTests,
        hasWidgets: true, bundleId: 'com.example.app', platform: 'ios');

    String listIn(String pbxproj, String targetId, String key) {
      final int target = pbxproj.indexOf('\t\t$targetId ');
      final int list = pbxproj.indexOf('$key = (', target);
      return pbxproj.substring(list, pbxproj.indexOf(');', list));
    }

    test('the extension is embedded in the application, not in the tests', () {
      final String out = spliced();

      expect(listIn(out, '97C146ED1CF9000F007C117D', 'buildPhases'),
          contains('Embed App Extensions'));
      expect(listIn(out, '331C8080294A63A400263BE5', 'buildPhases'),
          isNot(contains('Embed App Extensions')));
    });

    test('the application waits for it, not the tests', () {
      final String out = spliced();

      expect(listIn(out, '97C146ED1CF9000F007C117D', 'dependencies'),
          contains('PBXTargetDependency'));
      expect(listIn(out, '331C8080294A63A400263BE5', 'dependencies'),
          isNot(contains('PBXTargetDependency')));
    });

    test('taking the widgets away still gives the project back as it was', () {
      expect(
        dvApplePbxprojWithWidgets(spliced(),
            hasWidgets: false, bundleId: 'com.example.app', platform: 'ios'),
        withTests,
      );
    });
  });
}
