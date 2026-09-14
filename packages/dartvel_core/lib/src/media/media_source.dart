/// What a player plays, and what it needs to be allowed to.
library;

/// Where a [DVMediaSource] comes from.
enum DVMediaSourceKind { url, asset, file }

/// Whether a source is an adaptive stream.
enum DVMediaStreaming {
  /// Decided from the manifest extension: `.m3u8` is HLS, `.mpd` is DASH.
  auto,

  /// An adaptive stream whatever its URL looks like.
  adaptive,

  /// A single file, whatever its URL looks like.
  progressive,
}

/// The content protection systems `DVDrmAdapter`s answer for.
enum DVDrmScheme { widevine, fairPlay, playReady }

/// That a source is protected, and by what.
final class DVDrmProtection {
  const DVDrmProtection(this.scheme, {this.licenseUrl});

  final DVDrmScheme scheme;

  /// The content provider's licence server. Dartvel brokers no keys: this is
  /// handed to the adapter, never fetched by the runtime.
  final String? licenseUrl;
}

/// What is played. The box owns size and gestures; this owns content.
final class DVMediaSource {
  const DVMediaSource.url(
    String url, {
    this.streaming = DVMediaStreaming.auto,
    this.progressive,
    this.protection,
  })  : kind = DVMediaSourceKind.url,
        reference = url;

  const DVMediaSource.asset(
    String key, {
    this.streaming = DVMediaStreaming.auto,
    this.progressive,
    this.protection,
  })  : kind = DVMediaSourceKind.asset,
        reference = key;

  const DVMediaSource.file(
    String path, {
    this.streaming = DVMediaStreaming.auto,
    this.progressive,
    this.protection,
  })  : kind = DVMediaSourceKind.file,
        reference = path;

  const DVMediaSource._(
    this.kind,
    this.reference, {
    required this.streaming,
    required this.progressive,
    required this.protection,
  });

  final DVMediaSourceKind kind;

  /// The URL, asset key or file path, depending on [kind].
  final String reference;

  final DVMediaStreaming streaming;

  /// A single-file rendition of the same content, for a target that cannot
  /// play the adaptive stream. Without one such a target refuses the source
  /// rather than guessing at a URL.
  final String? progressive;

  /// Set when the content is protected.
  final DVDrmProtection? protection;

  /// Whether this is an HLS or DASH stream.
  bool get isAdaptive => switch (streaming) {
        DVMediaStreaming.adaptive => true,
        DVMediaStreaming.progressive => false,
        DVMediaStreaming.auto => _manifestExtension(reference),
      };

  /// The progressive rendition as a source of its own, or null.
  DVMediaSource? get progressiveRendition => progressive == null
      ? null
      : DVMediaSource._(
          kind,
          progressive!,
          streaming: DVMediaStreaming.progressive,
          progressive: null,
          protection: protection,
        );

  static bool _manifestExtension(String reference) {
    final Uri? uri = Uri.tryParse(reference);
    final String path = (uri?.path ?? reference).toLowerCase();
    return path.endsWith('.m3u8') || path.endsWith('.mpd');
  }

  @override
  bool operator ==(Object other) =>
      other is DVMediaSource &&
      other.kind == kind &&
      other.reference == reference &&
      other.streaming == streaming &&
      other.progressive == progressive &&
      other.protection?.scheme == protection?.scheme &&
      other.protection?.licenseUrl == protection?.licenseUrl;

  @override
  int get hashCode => Object.hash(kind, reference, streaming, progressive,
      protection?.scheme, protection?.licenseUrl);

  @override
  String toString() => 'DVMediaSource.${kind.name}($reference)';
}

/// A licence-acquiring integration for one or more [DVDrmScheme]s.
///
/// Adapters, labelled per target, and deliberately not a promise: Widevine on
/// Android and web, FairPlay on Apple platforms, PlayReady on Tizen and webOS.
abstract interface class DVDrmAdapter {
  Set<DVDrmScheme> get schemes;

  /// Whatever the target's player needs to decrypt [source] -- a licence, a
  /// key session handle. Opaque to the runtime, which only passes it on.
  Future<Object?> license(DVMediaSource source);
}

/// A span of media time, e.g. one buffered range.
final class DVRange {
  const DVRange(this.start, this.end);

  final Duration start;
  final Duration end;

  @override
  bool operator ==(Object other) =>
      other is DVRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DVRange($start, $end)';
}
