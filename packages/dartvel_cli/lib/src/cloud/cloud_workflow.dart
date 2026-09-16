/// The GitHub Actions workflow `dartvel build <target> --cloud` dispatches.
///
/// The build farm is the repository's own Actions: free for a public
/// repository, with macOS runners for iOS on a machine that is not a Mac, and
/// nothing between the developer and the runner that Dartvel operates. The
/// workflow is generated rather than hand-written so every project runs the
/// same one, and it is text that is compared byte for byte with the copy on
/// the branch being built: a build refuses to dispatch while they differ,
/// because a run of an older workflow succeeds at the wrong thing.
///
/// It is one workflow for every application in a repository. What differs per
/// run -- the application's directory, the target, the profile, a store to
/// publish to -- arrives as dispatch inputs, and inputs are read from the
/// environment inside scripts and never expanded into them: an application
/// directory is text, and `${{ }}` inside `run:` would make it shell.
library;

import 'dart:convert';

/// Where the workflow lives, relative to the repository root.
const String dvCloudWorkflowPath = '.github/workflows/dartvel-cloud.yml';

/// Its file name, which is how the dispatch API names a workflow.
const String dvCloudWorkflowFile = 'dartvel-cloud.yml';

/// The targets a cloud build can run, and the runner each one needs.
const Map<String, String> dvCloudRunners = <String, String>{
  'android': 'ubuntu-latest',
  'ios': 'macos-latest',
  'macos': 'macos-latest',
  'windows': 'windows-latest',
  'linux': 'ubuntu-latest',
  'web': 'ubuntu-latest',
  'web-server': 'ubuntu-latest',
};

List<String> get dvCloudTargets => dvCloudRunners.keys.toList();

const List<String> _profiles = <String>['development', 'profile', 'release'];

String _mode(String profile, {bool capital = false}) {
  final String mode = profile == 'development' ? 'debug' : profile;
  return capital ? '${mode[0].toUpperCase()}${mode.substring(1)}' : mode;
}

/// What `dartvel build [target] --profile [profile]` writes, relative to the
/// application.
String dvCloudArtifactPath(String target, String profile) => switch (target) {
      'android' => 'build/app/outputs/flutter-apk',
      'ios' => 'build/ios/iphoneos',
      'macos' => 'build/macos/Build/Products/${_mode(profile, capital: true)}',
      'windows' => 'build/windows/x64/runner/${_mode(profile, capital: true)}',
      'linux' => 'build/linux/x64/${_mode(profile)}/bundle',
      'web' => 'build/web',
      'web-server' => 'build/server',
      _ => throw ArgumentError.value(target, 'target', 'not a cloud target'),
    };

String dvCloudWorkflow({required String flutterVersion}) {
  final String runners = jsonEncode(dvCloudRunners);
  final StringBuffer cases = StringBuffer();
  for (final String target in dvCloudTargets) {
    for (final String profile in _profiles) {
      cases.writeln(
          '            $target/$profile) path=${dvCloudArtifactPath(target, profile)} ;;');
    }
  }
  return '''
# Written by `dartvel build <target> --cloud`. Every run is dispatched by that
# command (or `dartvel publish <store> --cloud`), which compares this file with
# the copy it would write and refuses to dispatch while they differ. Edit the
# generator in dartvel_cli rather than this file.
name: Dartvel Cloud
run-name: dartvel cloud \${{ inputs.target }} \${{ inputs.profile }} [\${{ inputs.request }}]

on:
  workflow_dispatch:
    inputs:
      app:
        description: The application directory, relative to the repository root.
        type: string
        default: .
      target:
        description: What dartvel build builds.
        type: choice
        options: [${dvCloudTargets.join(', ')}]
        required: true
      profile:
        description: The build profile.
        type: choice
        options: [${_profiles.join(', ')}]
        default: release
      publish:
        description: A store dartvel publish sends the build to afterwards, or empty.
        type: string
        default: ''
      dry_run:
        description: Pass --dry-run to dartvel publish.
        type: string
        default: 'false'
      request:
        description: Matches this run to the command that dispatched it.
        type: string
        default: ''

permissions:
  contents: read

jobs:
  build:
    name: dartvel build \${{ inputs.target }}
    runs-on: \${{ fromJSON('$runners')[inputs.target] }}
    timeout-minutes: 90
    env:
      APP: \${{ inputs.app }}
      TARGET: \${{ inputs.target }}
      PROFILE: \${{ inputs.profile }}
      PUBLISH: \${{ inputs.publish }}
      DRY_RUN: \${{ inputs.dry_run }}
    defaults:
      run:
        shell: bash
        working-directory: \${{ inputs.app }}
    steps:
      - uses: actions/checkout@v4

      - name: Java for Gradle
        if: inputs.target == 'android'
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '$flutterVersion'
          channel: stable
          cache: true

      - name: Cache Gradle
        if: inputs.target == 'android'
        uses: actions/cache@v4
        with:
          path: |
            ~/.gradle/caches
            ~/.gradle/wrapper
          key: gradle-\${{ runner.os }}-\${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}
          restore-keys: gradle-\${{ runner.os }}-

      - name: Cache cbindgen
        uses: actions/cache@v4
        with:
          path: ~/.cargo/bin/cbindgen
          key: cbindgen-\${{ runner.os }}-\${{ runner.arch }}

      - name: Install cbindgen when the app compiles the Rust runtime
        run: |
          if grep -q 'dartvel_shelf' pubspec.yaml && ! command -v cbindgen >/dev/null; then
            cargo install cbindgen --locked
          fi

      - name: Linux desktop dependencies
        if: inputs.target == 'linux'
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y -qq ninja-build libgtk-3-dev clang cmake pkg-config

      - name: flutter pub get
        run: flutter pub get

      - name: Android signing
        if: inputs.target == 'android'
        env:
          KEYSTORE: \${{ secrets.DARTVEL_ANDROID_KEYSTORE_BASE64 }}
          STORE_PASSWORD: \${{ secrets.DARTVEL_ANDROID_KEYSTORE_PASSWORD }}
          KEY_ALIAS: \${{ secrets.DARTVEL_ANDROID_KEY_ALIAS }}
          KEY_PASSWORD: \${{ secrets.DARTVEL_ANDROID_KEY_PASSWORD }}
        run: |
          if [ -z "\$KEYSTORE" ]; then
            echo "::notice::No DARTVEL_ANDROID_KEYSTORE_BASE64 secret, so a release build is signed with the debug key. dartvel key cloud --android-keystore sets it."
            exit 0
          fi
          printf '%s' "\$KEYSTORE" | base64 --decode > android/app/dartvel-upload.jks
          printf 'storeFile=dartvel-upload.jks\\nstorePassword=%s\\nkeyAlias=%s\\nkeyPassword=%s\\n' \\
            "\$STORE_PASSWORD" "\$KEY_ALIAS" "\${KEY_PASSWORD:-\$STORE_PASSWORD}" > android/key.properties
          grep -qs 'key.properties' android/app/build.gradle android/app/build.gradle.kts \\
            || echo "::warning::android/app/build.gradle does not read key.properties, so the keystore is written and not used."

      - name: dartvel build
        run: dart run dartvel_cli:dartvel build "\$TARGET" --profile "\$PROFILE"

      - name: Locate the artifact
        id: artifact
        run: |
          case "\$TARGET/\$PROFILE" in
${cases.toString().trimRight()}
            *) echo "::error::no artifact path for \$TARGET/\$PROFILE"; exit 1 ;;
          esac
          echo "path=\$APP/\$path" >> "\$GITHUB_OUTPUT"

      - uses: actions/upload-artifact@v4
        with:
          name: dartvel-\${{ inputs.target }}-\${{ inputs.profile }}
          path: \${{ steps.artifact.outputs.path }}
          if-no-files-found: error
          retention-days: 7

      - name: Credentials for dartvel publish
        if: inputs.publish != ''
        env:
          FIREBASE_SERVICE_ACCOUNT: \${{ secrets.DARTVEL_FIREBASE_SERVICE_ACCOUNT }}
        run: |
          if [ "\$PUBLISH" = firebase ] && [ -n "\$FIREBASE_SERVICE_ACCOUNT" ]; then
            printf '%s' "\$FIREBASE_SERVICE_ACCOUNT" > "\$RUNNER_TEMP/firebase.json"
            echo "GOOGLE_APPLICATION_CREDENTIALS=\$RUNNER_TEMP/firebase.json" >> "\$GITHUB_ENV"
          fi
          if [ "\$PUBLISH" = firebase ] && [ "\$DRY_RUN" != true ] && ! command -v firebase >/dev/null; then
            npm install -g firebase-tools
          fi

      - name: dartvel publish
        if: inputs.publish != ''
        run: |
          args=(publish "\$PUBLISH")
          if [ "\$DRY_RUN" = true ]; then args+=(--dry-run); fi
          dart run dartvel_cli:dartvel "\${args[@]}"
''';
}
