import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

import 'file_image_unsupported.dart'
    if (dart.library.io) 'file_image_io.dart';
import 'image_layout_stub.dart'
    if (dart.library.js_interop) 'image_layout_web.dart';
import 'stored_image.dart';

/// The variants `dartvel build web` wrote, handed over as
/// `--dart-define=DARTVEL_IMAGES=<json>`. Empty for any other build, which
/// then has none.
DVImageVariants _builtVariants() =>
    DVImageVariants.fromJson(const String.fromEnvironment('DARTVEL_IMAGES'));

/// Renders a [DVImage] model field.
///
/// [DVImage] is a value so models can serialize it; this is the widget half.
/// Generated model pages and cards use it for image fields.
///
/// On a web build with image variants it asks for the one its slot needs --
/// its laid-out width times the screen's pixel ratio, snapped to the
/// configured widths -- the way NextFaster's `srcset` does, so a phone
/// downloads the 640 and not the 3840. Everywhere else, and for a file or a
/// stored image, it fetches the image as it is.
class DVImageView extends StatelessWidget {
  final DVImage? image;

  /// Shown while a network image loads, when one is not available, and when
  /// the platform cannot read the source at all.
  final Widget? placeholder;

  final double? width;
  final double? height;
  final BoxFit fit;

  const DVImageView(
    this.image, {
    super.key,
    this.placeholder,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  /// The variants this build has. Set by the build; replaceable for tests.
  static DVImageVariants variants = _builtVariants();

  /// Back to what the build set.
  @visibleForTesting
  static void resetVariants() => variants = _builtVariants();

  @override
  Widget build(BuildContext context) {
    final source = image;
    if (source == null) return _placeholder;

    final DVImageVariants built = variants;
    final String? served = dvImageServedPath(source);
    // No layout pass unless there is a variant to choose: a LayoutBuilder
    // throws inside intrinsic sizing, and an application that configured
    // nothing must render exactly as it did.
    if (!built.isActive || served == null) {
      return _render(source, _providerFor(source));
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double slot = width ??
            (constraints.hasBoundedWidth
                ? constraints.maxWidth
                : source.width?.toDouble() ?? 0);
        dvRecordImageLayout(served, slot);
        final double ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
        return _render(
          source,
          dvImageVariantProvider(source, slot * ratio, built) ??
              _providerFor(source),
        );
      },
    );
  }

  Widget _render(DVImage source, ImageProvider<Object>? provider) {
    if (provider == null) return _placeholder;

    final rendered = Image(
      image: provider,
      width: width ?? source.width?.toDouble(),
      height: height ?? source.height?.toDouble(),
      fit: fit,
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
          _placeholder,
    );

    final alt = source.alt;
    if (alt == null || alt.isEmpty) {
      // An image with no alt text is decorative as far as a screen reader is
      // concerned; announcing its file name would be worse than silence.
      return ExcludeSemantics(child: rendered);
    }
    return Semantics(image: true, label: alt, child: rendered);
  }

  Widget get _placeholder => placeholder ?? SizedBox(width: width, height: height);

  static ImageProvider<Object>? _providerFor(DVImage image) {
    switch (image.source) {
      case DVImageSource.network:
        return NetworkImage(image.reference);
      case DVImageSource.asset:
        return AssetImage(image.reference);
      case DVImageSource.file:
        return fileImageProvider(image.reference);
      case DVImageSource.stored:
        return DVStoredImage(image.reference);
    }
  }
}

/// The address the site serves [image] at, which is what its variants are
/// keyed on: an asset under `assets/`, a network image at its own URL. Null
/// for a file or a stored image, which the site does not serve.
String? dvImageServedPath(DVImage image) => switch (image.source) {
      DVImageSource.asset => 'assets/${image.reference}',
      DVImageSource.network => image.reference,
      DVImageSource.file || DVImageSource.stored => null,
    };

/// The provider for [image] drawn [devicePixels] wide, or null when there is
/// no variant for it and the image itself is fetched.
///
/// The one place the address becomes a provider. The link prefetch goes
/// through [DVImageVariants.variantUrl] to the same address, so what it put
/// in the image cache is found under this key.
ImageProvider<Object>? dvImageVariantProvider(
  DVImage image,
  double devicePixels,
  DVImageVariants variants,
) {
  final String? served = dvImageServedPath(image);
  if (served == null) return null;
  final String? url = variants.variantUrl(served, devicePixels);
  return url == null ? null : NetworkImage(url);
}
