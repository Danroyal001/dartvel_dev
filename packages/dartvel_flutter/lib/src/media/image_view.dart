import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

import 'file_image_unsupported.dart'
    if (dart.library.io) 'file_image_io.dart';
import 'stored_image.dart';

/// Renders a [DVImage] model field.
///
/// [DVImage] is a value so models can serialize it; this is the widget half.
/// Generated model pages and cards use it for image fields.
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

  @override
  Widget build(BuildContext context) {
    final source = image;
    if (source == null) return _placeholder;

    final provider = _providerFor(source);
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
