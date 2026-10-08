import 'package:dartvel_cli/src/build/scene3d_native.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String _manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="app" android:icon="@mipmap/ic_launcher">
        <activity android:name=".MainActivity"/>
    </application>
</manifest>
''';

const String _plist = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
\t<key>CFBundleName</key>
\t<string>app</string>
</dict>
</plist>
''';

const String _linuxRunner = '''
static void my_application_activate(GApplication* application) {
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);
}
''';

const String _windowsRunner = '''
int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev, _In_ wchar_t *command_line, _In_ int show_command) {
  flutter::DartProject project(L"data");
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
}
''';

YamlMap _dartvel(String yaml) => loadYaml(yaml) as YamlMap;

void main() {
  group('dvScene3dEnabled', () {
    test('is on only for scene3d.enabled: true', () {
      expect(dvScene3dEnabled(_dartvel('scene3d:\n  enabled: true')), isTrue);
      expect(dvScene3dEnabled(_dartvel('scene3d:\n  enabled: false')), isFalse);
      expect(dvScene3dEnabled(_dartvel('scene3d: {}')), isFalse);
      expect(dvScene3dEnabled(_dartvel('other: 1')), isFalse);
    });
  });

  group('dvScene3dDependencyProblem', () {
    test('scene3d on without dartvel_scene is refused, with the fix', () {
      final String? problem = dvScene3dDependencyProblem(loadYaml('dartvel:\n  scene3d:\n    enabled: true\ndependencies:\n  flutter: {sdk: flutter}'));
      expect(problem, contains('dart pub add dartvel_scene'));
    });

    test('scene3d on with dartvel_scene, or off, is fine', () {
      expect(dvScene3dDependencyProblem(loadYaml('dartvel:\n  scene3d:\n    enabled: true\ndependencies:\n  dartvel_scene: ^0.11.4')), isNull);
      expect(dvScene3dDependencyProblem(loadYaml('dartvel:\n  pagesDir: lib/pages\ndependencies: {}')), isNull);
    });
  });

  group('Android', () {
    test('declares EnableFlutterGPU inside <application>, once', () {
      final String once = dvAndroidFlutterGpu(_manifest, enabled: true);
      expect(once, contains('android:name="io.flutter.embedding.android.EnableFlutterGPU"'));
      expect(once, contains('android:value="true"'));
      expect(once.indexOf('EnableFlutterGPU'), greaterThan(once.indexOf('<application')));
      expect(once.indexOf('EnableFlutterGPU'), lessThan(once.indexOf('</application>')));
      expect(dvAndroidFlutterGpu(once, enabled: true), once, reason: 'a second build changes nothing');
    });

    test('turning scene3d off takes the declaration back out', () {
      final String on = dvAndroidFlutterGpu(_manifest, enabled: true);
      expect(dvAndroidFlutterGpu(on, enabled: false), _manifest);
    });

    test("a developer's own declaration is kept and not duplicated", () {
      final String own = _manifest.replaceFirst('<activity',
          '<meta-data android:name="io.flutter.embedding.android.EnableFlutterGPU" android:value="true" />\n        <activity');
      expect(dvAndroidFlutterGpu(own, enabled: true), own);
    });
  });

  group('iOS and macOS', () {
    test('sets FLTEnableFlutterGPU in the top dictionary, idempotently, and removes it when off', () {
      final String on = dvAppleFlutterGpu(_plist, enabled: true);
      expect(on, contains('<key>FLTEnableFlutterGPU</key>'));
      expect(on.indexOf('FLTEnableFlutterGPU'), lessThan(on.lastIndexOf('</dict>')));
      expect(dvAppleFlutterGpu(on, enabled: true), on);
      expect(dvAppleFlutterGpu(on, enabled: false), _plist);
    });
  });

  group('Linux', () {
    test('enables Flutter GPU on the project right after it is made', () {
      final String on = dvLinuxFlutterGpu(_linuxRunner, enabled: true);
      final int made = on.indexOf('fl_dart_project_new()');
      final int set = on.indexOf('fl_dart_project_set_enable_flutter_gpu(project, TRUE);');
      expect(set, greaterThan(made));
      expect(set, lessThan(on.indexOf('fl_dart_project_set_dart_entrypoint_arguments')));
      expect(dvLinuxFlutterGpu(on, enabled: true), on);
      expect(dvLinuxFlutterGpu(on, enabled: false), _linuxRunner);
    });

    test('a runner with no project to set it on is left alone', () {
      expect(dvLinuxFlutterGpu('int main() {}\n', enabled: true), 'int main() {}\n');
    });
  });

  group('Windows', () {
    test('enables Flutter GPU on the DartProject', () {
      final String on = dvWindowsFlutterGpu(_windowsRunner, enabled: true);
      expect(on.indexOf('project.set_enable_flutter_gpu(true);'), greaterThan(on.indexOf('flutter::DartProject project(L"data");')));
      expect(dvWindowsFlutterGpu(on, enabled: true), on);
      expect(dvWindowsFlutterGpu(on, enabled: false), _windowsRunner);
    });
  });
}
