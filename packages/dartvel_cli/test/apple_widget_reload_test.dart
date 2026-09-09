// Telling WidgetKit that a published value has changed.
//
// The application writes into the App Group container and the extension
// reads it back on the timeline its provider asked for, which is fifteen
// minutes away. Until then the home screen shows the previous value, and
// there is nothing to distinguish that from a publish that did not work.
//
// WidgetCenter is what closes it and Dart cannot reach it: it is a Swift-only
// API with no Objective-C class to message, so there is nothing for
// objc_getClass to find. What can be reached is a Swift shim compiled into
// the application, which is what these cover -- the shim, and the Xcode
// wiring that makes it part of the binary.
//
// The wiring is where the silent failures are. A Swift file written into the
// project folder and not added to the Runner target's Sources phase is never
// compiled: the build succeeds, objc_getClass answers nil for ever, and every
// publish goes on being fifteen minutes late.
import 'package:dartvel_cli/src/build/apple_widget_reload.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String _pbxproj = '''
// !\$*UTF8*\$!
{
	archiveVersion = 1;
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
			);
		};
/* End PBXProject section */

/* Begin PBXSourcesBuildPhase section */
		97C146EA1CF9000F007C117D /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
/* End XCConfigurationList section */
	};
	rootObject = 97C146E61CF9000F007C117D /* Project object */;
}
''';

void main() {
  group('the shim', () {
    final String swift = dvAppleWidgetReloadSource();

    test('declares the class the Dart runtime looks up, under that name', () {
      // objc_getClass takes a string. Swift mangles a type name unless the
      // class is given an explicit Objective-C name, so a plain `@objc class`
      // is a class the lookup cannot find -- and a lookup that finds nothing
      // is indistinguishable from an application built without the shim,
      // which is a case this deliberately tolerates.
      expect(swift, contains('@objc($dvHomeWidgetAppleReloadClass)'));
      expect(swift, contains('class $dvHomeWidgetAppleReloadClass'));
      expect(swift, contains('NSObject'));
    });

    test('answers to the selector the Dart runtime sends', () {
      expect(swift, contains('func $dvHomeWidgetAppleReloadSelector('));
      expect(swift, contains('@objc'));
    });

    test('reloads every timeline, guarded by availability', () {
      // WidgetKit starts at iOS 14 and macOS 11, and a Flutter application's
      // deployment target is usually lower. Without the guard the file does
      // not compile, at the Xcode step, after everything in Dart passed.
      expect(swift, contains('reloadAllTimelines()'));
      expect(swift, contains('#available(iOS 14.0, macOS 11.0, *)'));
      expect(swift, contains('canImport(WidgetKit)'));
    });
  });

  group('the Xcode wiring', () {
    test('the shim is compiled into the application, not merely written out',
        () {
      // The silent one. A Swift file in the project folder that is in no
      // target's Sources phase is never compiled: the build succeeds, the
      // class is not in the binary, and every publish stays fifteen minutes
      // late with nothing to read anywhere.
      final String out = dvApplePbxprojWithWidgetReload(_pbxproj,
          hasWidgets: true, platform: 'ios');

      final int phase = out.indexOf('/* Begin PBXSourcesBuildPhase section */');
      final int phaseEnd = out.indexOf('/* End PBXSourcesBuildPhase section */');
      expect(out.substring(phase, phaseEnd),
          contains(dvAppleWidgetReloadFileName));

      // And the build file it names has to exist, or Xcode refuses to open
      // the project -- which is at least loud.
      expect(out, contains('/* Begin PBXBuildFile section */'));
      final int buildFiles = out.indexOf('/* Begin PBXBuildFile section */');
      final int buildFilesEnd = out.indexOf('/* End PBXBuildFile section */');
      expect(out.substring(buildFiles, buildFilesEnd),
          contains(dvAppleWidgetReloadFileName));
    });

    test('the file is in the navigator, under the application group', () {
      final String out = dvApplePbxprojWithWidgetReload(_pbxproj,
          hasWidgets: true, platform: 'ios');
      final int group = out.indexOf('/* Begin PBXGroup section */');
      final int groupEnd = out.indexOf('/* End PBXGroup section */');

      expect(out.substring(group, groupEnd),
          contains(dvAppleWidgetReloadFileName));
    });

    test('taking the widgets away gives the project back exactly as it was',
        () {
      // The pbxproj is checked in. A build that rewrote it differently every
      // time would put a diff on every branch, and one that left objects
      // behind would leave Xcode a reference to a file that is gone.
      final String added = dvApplePbxprojWithWidgetReload(_pbxproj,
          hasWidgets: true, platform: 'ios');
      final String removed = dvApplePbxprojWithWidgetReload(added,
          hasWidgets: false, platform: 'ios');

      expect(removed, _pbxproj);
    });

    test('a second build does not add it twice', () {
      final String once = dvApplePbxprojWithWidgetReload(_pbxproj,
          hasWidgets: true, platform: 'ios');
      final String twice = dvApplePbxprojWithWidgetReload(once,
          hasWidgets: true, platform: 'ios');

      expect(twice, once);
    });

    test('macOS is wired the same way', () {
      // macOS packages the same WidgetKit extension, so it has the same
      // fifteen-minute gap and needs the same shim. A platform that got the
      // extension and not the reload would be the harder half of a bug that
      // only shows up as staleness.
      final String out = dvApplePbxprojWithWidgetReload(_pbxproj,
          hasWidgets: true, platform: 'macos');
      final int phase = out.indexOf('/* Begin PBXSourcesBuildPhase section */');
      final int phaseEnd = out.indexOf('/* End PBXSourcesBuildPhase section */');

      expect(out.substring(phase, phaseEnd),
          contains(dvAppleWidgetReloadFileName));
    });

    test('a project with no application target is left alone', () {
      // Rather than half-spliced. A pbxproj this does not understand is
      // somebody's own, and a build tool that writes into one it cannot read
      // trades a missing feature for a project that will not open.
      const String noTarget = '{\n\tobjects = {\n\t};\n}\n';

      expect(
        dvApplePbxprojWithWidgetReload(noTarget,
            hasWidgets: true, platform: 'ios'),
        noTarget,
      );
    });
  });
}
