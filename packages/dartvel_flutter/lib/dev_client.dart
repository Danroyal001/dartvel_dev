/// The dev-client shell.
///
/// Imported by the entrypoint `dartvel build dev-client` generates, and by
/// nothing an application imports. That is the whole of the release-build
/// guarantee: Dart compiles what the entrypoint reaches, and a release build's
/// entrypoint cannot reach this library, so there is no runtime flag that
/// could switch a dev menu on in a shipped application.
library dartvel_flutter.dev_client;

export 'package:dartvel_core/dartvel.dart'
    show
        DVDevClientManifest,
        DVDevClientPairing,
        DVDevClientRefusal,
        DVDevClientSigner,
        DVSignedBundle,
        DVSignedBundleException,
        dvDevClientBundlePath,
        dvDevClientBundleVersion,
        dvDevClientCompatibility,
        dvDevClientLinkScheme,
        dvDevClientMissingBinding,
        dvDevClientPublicTrack,
        dvDevClientShellMarker,
        dvDevClientUnreachable,
        dvSignedBundleFormat;

export 'src/devclient/dev_client.dart';
