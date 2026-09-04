// Whether an Android SDK is installed, asked the way Flutter asks it.
//
// The check was `sdkmanager` on PATH. A GitHub runner ships an Android SDK
// and does not put sdkmanager on PATH; Android Studio installs one that only
// its own shell knows about. So `dartvel build android` refused on machines
// that build Android perfectly well, and the refusal told the person to
// install the SDK they already had.
import 'dart:io';

import 'package:dartvel_cli/src/utils/android_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// An SDK directory shaped like a real one.
Directory sdk({bool withPlatforms = true}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_sdk_');
  addTearDown(() => root.deleteSync(recursive: true));
  if (withPlatforms) {
    Directory(p.join(root.path, 'platforms', 'android-34'))
        .createSync(recursive: true);
  }
  return root;
}

void main() {
  test('a directory with platforms in it is an SDK', () {
    expect(dvAndroidSdkAt(sdk().path), isTrue);
  });

  test('a directory that merely exists is not', () {
    // ANDROID_HOME pointing at an empty or half-deleted directory is
    // common, and reading it as an SDK turns a clear refusal into a Gradle
    // error twenty lines long.
    expect(dvAndroidSdkAt(sdk(withPlatforms: false).path), isFalse);
    expect(dvAndroidSdkAt('/nowhere/at/all'), isFalse);
    expect(dvAndroidSdkAt(null), isFalse);
    expect(dvAndroidSdkAt(''), isFalse);
  });

  test('either environment variable answers', () {
    // Flutter reads both, and which one is set differs by how the SDK was
    // installed. Reading one of them is the same bug in a smaller size.
    final Directory installed = sdk();

    expect(
      dvAndroidSdkInstalled(
        environment: <String, String>{'ANDROID_HOME': installed.path},
        onPath: (String _) => false,
      ),
      isTrue,
    );
    expect(
      dvAndroidSdkInstalled(
        environment: <String, String>{'ANDROID_SDK_ROOT': installed.path},
        onPath: (String _) => false,
      ),
      isTrue,
    );
  });

  test('sdkmanager on PATH still counts', () {
    // The old answer was not wrong, only incomplete.
    expect(
      dvAndroidSdkInstalled(
        environment: const <String, String>{},
        onPath: (String tool) => tool == 'sdkmanager',
      ),
      isTrue,
    );
  });

  test('neither is neither', () {
    expect(
      dvAndroidSdkInstalled(
        environment: const <String, String>{'ANDROID_HOME': '/nowhere'},
        onPath: (String _) => false,
      ),
      isFalse,
    );
  });
}
