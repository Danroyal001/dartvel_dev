/// The PDFium build every target bundles, pinned with each archive's sha256.
///
/// From bblanchon/pdfium-binaries, which builds Chromium's PDFium for every
/// platform Dartvel targets. A release is adopted once it has been out a few
/// weeks; the build hook downloads the archive for the target, refuses it if
/// its sha256 differs from the one here, and caches it, so a build after the
/// first does not touch the network.
library;

/// The release tag.
const String dvPdfiumRelease = 'chromium/8076';

/// One target's archive: its name on the release, its sha256, and where the
/// library sits inside it.
class DVPdfiumArchive {
  const DVPdfiumArchive(this.name, this.sha256, this.library);

  final String name;
  final String sha256;

  /// The library's path inside the archive.
  final String library;

  Uri get url => Uri.parse(
      'https://github.com/bblanchon/pdfium-binaries/releases/download/${Uri.encodeComponent(dvPdfiumRelease)}/$name');
}

/// Archives by `<os>-<arch>`, as the build hook names the target.
const Map<String, DVPdfiumArchive> dvPdfiumArchives = <String, DVPdfiumArchive>{
  'linux-x64': DVPdfiumArchive(
      'pdfium-linux-x64.tgz', 'd9d67bc40af03aef4fe28a60b19b1086f28ace019c8c9caf19cb7fe3d14ceca3', 'lib/libpdfium.so'),
  'linux-arm64': DVPdfiumArchive(
      'pdfium-linux-arm64.tgz', 'd7247b33ae5545615a5e877235dd97afc879e3a8805689684f528cae3339d352', 'lib/libpdfium.so'),
  'windows-x64': DVPdfiumArchive(
      'pdfium-win-x64.tgz', '808d36da9bc5a3104315fb307c80998121f565ee53953633bf33e80d7429e5ac', 'bin/pdfium.dll'),
  'windows-arm64': DVPdfiumArchive(
      'pdfium-win-arm64.tgz', 'ab7c45c25fc8456fd9b94666ce3dd27a940f4984f54b328f012468f869d34346', 'bin/pdfium.dll'),
  'macos-x64': DVPdfiumArchive(
      'pdfium-mac-x64.tgz', '40865f34642c34d82cc336132df9e0347133f4692cd46776647af160f9a5cca9', 'lib/libpdfium.dylib'),
  'macos-arm64': DVPdfiumArchive(
      'pdfium-mac-arm64.tgz', '0d6781fe08906baff3d82c90953e519fbc4eb253fe76431e5ed53b157763b97c', 'lib/libpdfium.dylib'),
  'android-arm64': DVPdfiumArchive(
      'pdfium-android-arm64.tgz', 'b7a6919dc130dfdf7e409bd1762ed2a306408c4faee1173668837fc446217bf7', 'lib/libpdfium.so'),
  'android-x64': DVPdfiumArchive(
      'pdfium-android-x64.tgz', '9d043689096c7cdd4ca98fff95599be115b2a38feba0c68d2a79ba5eedbda415', 'lib/libpdfium.so'),
  'ios-arm64': DVPdfiumArchive(
      'pdfium-ios-device-arm64.tgz', 'c44140e03fc1e243bebb25fe964e78d2c1fcce32b1f03cfce1ef40617a882304', 'lib/libpdfium.dylib'),
  'iossimulator-arm64': DVPdfiumArchive(
      'pdfium-ios-simulator-arm64.tgz', '1bb98039d8148da5f908027eab5a11c85f0d3e31d4205f57168278c55f846b6e', 'lib/libpdfium.dylib'),
  'iossimulator-x64': DVPdfiumArchive(
      'pdfium-ios-simulator-x64.tgz', 'cd0db9f41bf829426575d6ce27001520cf260e903790febac152653116cfb3c2', 'lib/libpdfium.dylib'),
};

/// The archive for a target, or null where PDFium has no build (the web,
/// Fuchsia, 32-bit targets): those answer with a reason instead.
DVPdfiumArchive? dvPdfiumArchiveFor(String os, String arch, {bool simulator = false}) =>
    dvPdfiumArchives[os == 'ios' && simulator ? 'iossimulator-$arch' : '$os-$arch'];
