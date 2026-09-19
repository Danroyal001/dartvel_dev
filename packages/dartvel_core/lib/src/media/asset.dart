/// The files an application bundles, as values rather than paths.
///
/// `dartvel routes` reads `pubspec.yaml` and writes a `DVAsset` enum with one
/// value per bundled file, named from the file and carrying what it is, so a
/// page says `DVBox.image(DVAsset.logoSmall)`. A path in a string is checked
/// by nothing: a renamed file, a typo, or an asset never listed passes every
/// build and shows a blank box on a device.
library dartvel_core.media.asset;

import 'image.dart';
import 'media_source.dart';

/// What a bundled file is, taken from its extension when it is generated.
enum DVAssetKind {
  image,
  video,
  audio,
  font,

  /// A 3D model: `.glb`, `.gltf`, `.usdz`.
  model3d,

  /// Anything else the application bundles and reads itself.
  data,
}

/// One bundled file. The generated `DVAsset` enum implements this.
abstract interface class DVAssetRef {
  /// The path the bundle holds it under, as `pubspec.yaml` declares it.
  String get path;

  /// What it is.
  DVAssetKind get kind;

}

/// What can be shown as an image: an image a model holds, or a bundled one.
extension DVAssetImage on DVAssetRef {
  /// This asset as an image.
  ///
  /// Refuses an asset that is not one, naming it: a video passed where an
  /// image is expected would otherwise be an empty box on a device.
  DVImage get image {
    if (kind != DVAssetKind.image) {
      throw ArgumentError.value(
        '$this',
        'asset',
        'is a ${kind.name}, and an image was asked for',
      );
    }
    return DVImage.asset(path);
  }
}

/// What can be played: media a model holds, or a bundled file.
extension DVAssetMedia on DVAssetRef {
  /// This asset as something to play.
  ///
  /// Refuses an asset that is neither video nor audio, naming it.
  DVMediaSource get media {
    if (kind != DVAssetKind.video && kind != DVAssetKind.audio) {
      throw ArgumentError.value(
        '$this',
        'asset',
        'is a ${kind.name}, and a video or a sound was asked for',
      );
    }
    return DVMediaSource.asset(path);
  }
}

/// The image [source] names: a [DVImage] as it is, or a bundled image, with
/// [alt] when the caller has better words for it than the value carries.
///
/// Anything else is refused rather than rendered as an empty box.
DVImage dvImageOf(Object source, {String? alt}) {
  if (source is DVImage) {
    return alt == null ? source : source.copyWith(alt: alt);
  }
  if (source is DVAssetRef) {
    final DVImage image = source.image;
    return alt == null ? image : image.copyWith(alt: alt);
  }
  throw ArgumentError.value(
    source,
    'source',
    'is not an image. Pass a DVImage or a bundled DVAsset',
  );
}

/// The media [source] names: a [DVMediaSource] as it is, or a bundled file.
DVMediaSource dvMediaOf(Object source) {
  if (source is DVMediaSource) return source;
  if (source is DVAssetRef) return source.media;
  throw ArgumentError.value(
    source,
    'source',
    'is not something to play. Pass a DVMediaSource or a bundled DVAsset',
  );
}
