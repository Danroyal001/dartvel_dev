/// The one way `dartvel build` is told what kind of build to make.
///
/// There used to be two: a `--release` flag that defaulted to true and a
/// `--profile` flag beside it, so a debug build was `--no-release` and a
/// command could say both. And the development shell was a separate
/// `dartvel build dev-client` subcommand, when what it is -- a Flutter debug
/// build that a dev server can reload -- is a mode of the ordinary build.
library dartvel_cli.build.build_profile;

enum DVBuildProfile {
  /// Flutter debug (JIT). On Android it also carries the dev-client pairing
  /// and tunnel, so `dartvel dev` can hot reload it over the network.
  development('--debug'),

  /// Flutter profile mode: AOT, with the performance tooling left in.
  profile('--profile'),

  /// Flutter release mode.
  release('--release');

  const DVBuildProfile(this.flutterFlag);

  /// The flag `flutter build` is given for this profile.
  final String flutterFlag;

  bool get isDevelopment => this == DVBuildProfile.development;

  /// The values `--profile` accepts, in the order help lists them.
  static List<String> get names =>
      <String>[for (final DVBuildProfile p in values) p.name];

  static DVBuildProfile parse(String name) {
    for (final DVBuildProfile profile in values) {
      if (profile.name == name) return profile;
    }
    throw FormatException(
      '"$name" is not a build profile. Use ${names.join(', ')}.',
    );
  }
}
