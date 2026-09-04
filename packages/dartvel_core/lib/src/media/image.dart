/// Where a [DVImage]'s bytes come from.
enum DVImageSource {
  /// A remote URL, fetched at render time.
  network,

  /// An asset bundled with the application.
  asset,

  /// A path on the local filesystem. Not available on the web.
  file,

  /// A key in `DV.FileStorage`: bytes the application holds itself.
  ///
  /// The other three name something outside the application -- an address, a
  /// bundled file, a path on a disk. This one does not, which is what an
  /// imported design needs: a Figma import writes the URL Figma hands back,
  /// those expire, and a page that looked right on the day it was imported
  /// shows broken images a fortnight later. Stored bytes have nothing to
  /// expire, need no build step, and work wherever the storage adapter does.
  stored,
}

/// An image held by a model field.
///
/// Models are serialized to JSON for persistence, transport and generated
/// clients, so an image field has to be a value rather than a widget. Rendering
/// belongs to the UI layer, which reads [source] and [reference].
class DVImage {
  /// How [reference] should be resolved.
  final DVImageSource source;

  /// The URL, asset key, or file path, depending on [source].
  final String reference;

  /// Alternative text. Generated pages use it for accessibility, and SEO uses
  /// it for the OG image description.
  final String? alt;

  /// Intrinsic width in pixels, when known. Generated pages use it to reserve
  /// space, which avoids layout shift before the image loads.
  final int? width;

  /// Intrinsic height in pixels, when known.
  final int? height;

  const DVImage({
    required this.source,
    required this.reference,
    this.alt,
    this.width,
    this.height,
  });

  const DVImage.network(
    String url, {
    String? alt,
    int? width,
    int? height,
  }) : this(
          source: DVImageSource.network,
          reference: url,
          alt: alt,
          width: width,
          height: height,
        );

  const DVImage.asset(
    String assetKey, {
    String? alt,
    int? width,
    int? height,
  }) : this(
          source: DVImageSource.asset,
          reference: assetKey,
          alt: alt,
          width: width,
          height: height,
        );

  const DVImage.file(
    String path, {
    String? alt,
    int? width,
    int? height,
  }) : this(
          source: DVImageSource.file,
          reference: path,
          alt: alt,
          width: width,
          height: height,
        );

  const DVImage.stored(
    String key, {
    String? alt,
    int? width,
    int? height,
  }) : this(
          source: DVImageSource.stored,
          reference: key,
          alt: alt,
          width: width,
          height: height,
        );

  /// Reads an image from a model's JSON.
  ///
  /// A bare string is accepted and read as a network URL, because that is what
  /// an existing API commonly sends for an image column.
  static DVImage? fromJson(Object? json) {
    if (json == null) return null;
    if (json is DVImage) return json;
    if (json is String) {
      return json.isEmpty ? null : DVImage.network(json);
    }
    if (json is! Map) {
      throw ArgumentError.value(
        json,
        'json',
        'A DVImage must be a map or a URL string, not ${json.runtimeType}.',
      );
    }

    final reference = json['reference'] ?? json['url'] ?? json['src'];
    if (reference is! String || reference.isEmpty) {
      throw ArgumentError.value(
        json,
        'json',
        'A DVImage needs a non-empty "reference", "url" or "src".',
      );
    }

    final sourceName = json['source'];
    final source = DVImageSource.values.where(
      (DVImageSource value) => value.name == sourceName,
    );
    return DVImage(
      source: source.isEmpty ? DVImageSource.network : source.first,
      reference: reference,
      alt: json['alt'] as String?,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'source': source.name,
        'reference': reference,
        if (alt != null) 'alt': alt,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      };

  DVImage copyWith({
    DVImageSource? source,
    String? reference,
    String? alt,
    int? width,
    int? height,
  }) {
    return DVImage(
      source: source ?? this.source,
      reference: reference ?? this.reference,
      alt: alt ?? this.alt,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DVImage &&
      other.source == source &&
      other.reference == reference &&
      other.alt == alt &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(source, reference, alt, width, height);

  @override
  String toString() => 'DVImage(${source.name}: $reference)';
}
