// The Swift `dartvel build ios` compiles into the application for drag and
// drop, and the Xcode wiring that makes it part of the binary. A Swift file
// that is not in the Runner target's Sources phase is never compiled, and
// then objc_getClass answers nil -- the same answer an application built
// with plain `flutter build` gives -- so the wiring is what is tested.
import 'dart:io';

import 'package:dartvel_cli/src/build/apple_widget_reload.dart';
import 'package:dartvel_cli/src/build/ios_drag_drop_bridge.dart';
import 'package:dartvel_core/dartvel.dart' show dvIosDragDropClass;
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
  test('the bridge is compiled into the application target', () {
    final String out = dvIosPbxprojWithDragDrop(_pbxproj);
    expect(out, contains('$dvIosDragDropFileName in Sources'));
    expect(out, contains('path = $dvIosDragDropFileName;'));
    final int sources = out.indexOf('isa = PBXSourcesBuildPhase;');
    expect(sources, greaterThan(0));
  });

  test('it is written once however many builds run', () {
    final String once = dvIosPbxprojWithDragDrop(_pbxproj);
    expect(dvIosPbxprojWithDragDrop(once), once);
  });

  test('it lives beside the widget reload shim without disturbing it', () {
    final String both = dvIosPbxprojWithDragDrop(
        dvApplePbxprojWithWidgetReload(_pbxproj, hasWidgets: true, platform: 'ios'));
    expect(both, contains(dvAppleWidgetReloadFileName));
    expect(both, contains(dvIosDragDropFileName));
    expect(dvApplePbxprojWithWidgetReload(both, hasWidgets: false, platform: 'ios'),
        dvIosPbxprojWithDragDrop(_pbxproj),
        reason: 'removing the widgets takes only their shim out');
  });

  test('the Swift names the class and selectors the runtime sends', () {
    final String swift = dvIosDragDropSource();
    expect(swift, contains('@objc($dvIosDragDropClass)'));
    for (final String selector in dvIosDragDropSelectors) {
      expect(swift, contains('@objc($selector)'), reason: selector);
    }
    expect(swift, contains('UIDropInteraction('));
    expect(swift, contains('UIDragInteraction('));
    expect(swift, contains('isEnabled = true'),
        reason: 'UIDragInteraction is off by default on iPhone');
  });

  test('every iOS build writes it', () {
    final String build = File('lib/src/commands/build_command.dart').readAsStringSync();
    expect(build, contains('dvIosDragDropSource()'));
    expect(build, contains('dvIosPbxprojWithDragDrop('));
  });
}
