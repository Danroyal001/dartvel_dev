// Every platform `dartvel build` knows is in Studio's Deploy menu, the ones
// that do not build today included, each saying where it stands.
//
// The menu used to show six groups -- Website, Phones and tablets, and so on
// -- and nothing under them, so an owner could not tell that LG TVs were a
// target at all, let alone that they do not build yet. A target left out
// reads as unsupported for good; one listed with its reason reads as work in
// progress, which is the truth.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// `dartvel build` platforms, from `buildPlatformArguments` in dartvel_cli,
/// less the aliases and packaging formats (`tpk`, `-iso`, `-img`, `-tui`) and
/// `all`.
const Set<String> cliPlatforms = <String>{
  'web', 'web-server', 'android', 'ios', 'fireos', 'windows', 'macos',
  'linux', 'linux-cli', 'macos-cli', 'windows-cli', 'fuchsia-cli', 'tizen',
  'sony-elinux', 'webos', 'tvos', 'fuchsia', 'vscode', 'chrome-extension',
  'firefox-extension',
};

void main() {
  test('every platform dartvel build knows is listed', () {
    expect(<String>{
      for (final DVDeployPlatform platform in DVDeployPlatform.values)
        ...platform.commands,
    }, cliPlatforms);
  });

  test('each sits in the group an app on it serves pages for', () {
    DVDeployTarget groupOf(String command) => DVDeployPlatform.values
        .firstWhere((DVDeployPlatform p) => p.commands.contains(command))
        .target;

    expect(groupOf('web-server'), DVDeployTarget.web);
    expect(groupOf('fireos'), DVDeployTarget.phones);
    expect(groupOf('linux-cli'), DVDeployTarget.desktop);
    expect(groupOf('webos'), DVDeployTarget.tvs);
    expect(groupOf('vscode'), DVDeployTarget.extensions);
    expect(groupOf('sony-elinux'), DVDeployTarget.devices);
    expect(groupOf('fuchsia'), DVDeployTarget.devices);
  });

  test('a platform that does not build today says so, and why', () {
    for (final DVDeployPlatform platform in DVDeployPlatform.values) {
      if (platform.status == DVDeployStatus.ready) continue;
      expect(platform.reason, isNotEmpty, reason: platform.label);
    }
    expect(DVDeployPlatform.lgTvs.status, DVDeployStatus.notYet);
    expect(DVDeployPlatform.lgTvs.reason, contains('Dart'));
    expect(DVDeployPlatform.fuchsia.status, DVDeployStatus.notYet);
    expect(DVDeployPlatform.web.status, DVDeployStatus.ready);
  });
}
