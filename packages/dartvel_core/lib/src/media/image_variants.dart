/// Image variants: the widths Dartvel resizes an image to, the one address a
/// variant is asked for by, and what a server refuses to fetch.
///
/// NextFaster serves every image at one of a fixed set of widths, and its
/// links prefetch the one the visitor's screen will use. The widget, the link
/// prefetch and the server have to agree on that address to the byte -- a
/// prefetch of a slightly different URL is a second download, not a cache hit
/// -- so it is worked out here, once, and each of them calls this.
library;

import 'dart:convert';

/// Next.js's device and image sizes, which are what most layouts land on.
const List<int> dvDefaultImageWidths = <int>[
  16, 32, 48, 64, 96, 128, 256, 384, //
  640, 750, 828, 1080, 1200, 1920, 2048, 3840,
];

/// Where a web-server build answers variant requests, relative to the site.
const String dvImageEndpointPath = '_dartvel/image';

/// Where `dartvel build web` writes the variants of the application's
/// images, relative to the site: `<dir>/<width>/<the image's own path>`.
const String dvStaticImageVariantDir = 'assets/_dartvel/img';

/// The formats a variant can be made from.
const Set<String> dvRasterImageExtensions = <String>{
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', //
};

const int _maxWidth = 8192;

/// The widths images are resized to, and what can be resized.
///
/// Read from `dartvel.images` in pubspec.yaml by the build, which adds what
/// it knows about the build itself -- whether a server answers
/// [dvImageEndpointPath], and which images it wrote variants of -- and hands
/// the whole of it to the application. An application built without it has
/// no variants: [isActive] is false and every image is fetched as it is.
class DVImageVariants {
  const DVImageVariants({
    this.widths = dvDefaultImageWidths,
    this.quality = 75,
    this.remoteHosts = const <String>[],
    this.endpoint = false,
    this.assetWidths = const <String, int>{},
  });

  /// Ascending. A request for any other width is refused.
  final List<int> widths;

  /// For lossy formats; 1 to 100.
  final int quality;

  /// Hosts whose images the server will fetch and resize. `*.example.com`
  /// allows the subdomains of example.com and not example.com itself.
  final List<String> remoteHosts;

  /// Whether a server answers [dvImageEndpointPath]: true on a web-server
  /// build, false on a static one, where there is nothing to answer it.
  final bool endpoint;

  /// The width of each image the build wrote variants of, by the path the
  /// site serves it at (`assets/assets/hero.png`). A variant as wide as the
  /// image or wider is never written, so the image itself is used instead.
  final Map<String, int> assetWidths;

  /// Whether this build has any variants at all.
  bool get isActive => endpoint || assetWidths.isNotEmpty;

  /// The smallest configured width covering [devicePixels], or the largest.
  int snap(double devicePixels) {
    for (final int width in widths) {
      if (width >= devicePixels) return width;
    }
    return widths.isEmpty ? devicePixels.ceil() : widths.last;
  }

  /// Whether the server may fetch images from [host].
  bool allowsHost(String host) {
    final String name = host.toLowerCase();
    for (final String allowed in remoteHosts) {
      final String pattern = allowed.toLowerCase();
      if (pattern.startsWith('*.')) {
        if (name.endsWith(pattern.substring(1))) return true;
      } else if (name == pattern) {
        return true;
      }
    }
    return false;
  }

  /// Where [src] drawn [devicePixels] wide is fetched from, or null to fetch
  /// [src] itself.
  ///
  /// [src] is a path the site serves (`assets/assets/hero.png`) or an http(s)
  /// address. The same answer for the widget that draws the image and the
  /// link that prefetches it, which is the point of it being here.
  String? variantUrl(String src, double devicePixels) {
    final int width = snap(devicePixels);
    final Uri? remote = _remote(src);
    if (remote == null) {
      final int? source = assetWidths[src];
      if (source != null) {
        return width >= source ? null : '$dvStaticImageVariantDir/$width/$src';
      }
      return endpoint && dvIsLocalImagePath(src) ? _endpoint(src, width) : null;
    }
    return endpoint && allowsHost(remote.host) ? _endpoint(src, width) : null;
  }

  String _endpoint(String src, int width) =>
      '$dvImageEndpointPath?src=${Uri.encodeQueryComponent(src)}'
      '&w=$width&q=$quality';

  /// `dartvel.images` from pubspec.yaml, and what in it was not accepted.
  ///
  /// A value that cannot be used is reported and replaced by the default,
  /// rather than failing the build or being quietly dropped.
  static ({DVImageVariants variants, List<String> problems}) parse(
    Object? section,
  ) {
    if (section == null) {
      return (variants: const DVImageVariants(), problems: const <String>[]);
    }
    if (section is! Map) {
      return (
        variants: const DVImageVariants(),
        problems: <String>['dartvel.images must be a map'],
      );
    }
    final List<String> problems = <String>[];

    List<int> widths = dvDefaultImageWidths;
    final Object? rawWidths = section['widths'];
    if (rawWidths != null) {
      if (rawWidths is! List) {
        problems.add('dartvel.images.widths must be a list of widths');
      } else {
        final Set<int> accepted = <int>{};
        final List<Object?> rejected = <Object?>[];
        for (final Object? width in rawWidths) {
          if (width is int && width > 0 && width <= _maxWidth) {
            accepted.add(width);
          } else {
            rejected.add(width);
          }
        }
        if (rejected.isNotEmpty) {
          problems.add('dartvel.images.widths: not widths between 1 and '
              '$_maxWidth: ${rejected.join(', ')}');
        }
        if (accepted.isNotEmpty) widths = accepted.toList()..sort();
      }
    }

    int quality = 75;
    final Object? rawQuality = section['quality'];
    if (rawQuality != null) {
      if (rawQuality is int && rawQuality >= 1 && rawQuality <= 100) {
        quality = rawQuality;
      } else {
        problems.add('dartvel.images.quality must be 1 to 100, not '
            '$rawQuality');
      }
    }

    List<String> hosts = const <String>[];
    final Object? rawHosts = section['remoteHosts'];
    if (rawHosts != null) {
      if (rawHosts is List && rawHosts.every((Object? h) => h is String)) {
        hosts = <String>[
          for (final Object? host in rawHosts)
            if ((host! as String).trim().isNotEmpty) (host as String).trim(),
        ];
      } else {
        problems.add('dartvel.images.remoteHosts must be a list of host '
            'names');
      }
    }

    return (
      variants: DVImageVariants(
        widths: widths,
        quality: quality,
        remoteHosts: hosts,
      ),
      problems: problems,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'widths': widths,
        'quality': quality,
        'remoteHosts': remoteHosts,
        'endpoint': endpoint,
        'assetWidths': assetWidths,
      };

  /// [toJson] as a `--dart-define` value: base64url, because the flutter
  /// tool splits a define's value at commas and a JSON object is full of
  /// them.
  String toDartDefine() =>
      base64Url.encode(utf8.encode(jsonEncode(toJson()))).replaceAll('=', '');

  /// What [toJson] wrote, as a map, as its JSON text or as [toDartDefine]'s
  /// base64url. Anything unreadable is a build with no variants, never an
  /// exception: this runs as the application starts.
  static DVImageVariants fromJson(Object? json) {
    Object? value = json;
    if (value is String) {
      if (value.isEmpty) return const DVImageVariants();
      try {
        String text = value.trim();
        if (!text.startsWith('{')) {
          final String padded = text.padRight((text.length + 3) & ~3, '=');
          text = utf8.decode(base64Url.decode(padded));
        }
        value = jsonDecode(text);
      } on FormatException {
        return const DVImageVariants();
      }
    }
    if (value is! Map) return const DVImageVariants();
    final List<int> widths = <int>[
      for (final Object? w in (value['widths'] as List?) ?? const <Object?>[])
        if (w is int && w > 0) w,
    ]..sort();
    final Object? quality = value['quality'];
    return DVImageVariants(
      widths: widths.isEmpty ? dvDefaultImageWidths : widths,
      quality: quality is int && quality >= 1 && quality <= 100 ? quality : 75,
      remoteHosts: <String>[
        for (final Object? h
            in (value['remoteHosts'] as List?) ?? const <Object?>[])
          if (h is String) h,
      ],
      endpoint: value['endpoint'] == true,
      assetWidths: <String, int>{
        for (final MapEntry<Object?, Object?> e
            in ((value['assetWidths'] as Map?) ?? const <Object?, Object?>{})
                .entries)
          if (e.key is String && e.value is int) e.key! as String: e.value! as int,
      },
    );
  }
}

/// Whether [src] is an image path inside the site: relative, with no `.` or
/// `..` segment, no empty segment, nothing that a filesystem or a URL parser
/// could read as a drive, a scheme or an escape, and an image's extension.
///
/// Deliberately stricter than it needs to be for any real asset name. A `%`
/// is refused because the query has already been decoded once, and a second
/// decoding somewhere below is how `%2e%2e` becomes `..`.
bool dvIsLocalImagePath(String src) {
  if (src.isEmpty || src.length > 2048) return false;
  if (src.startsWith('/')) return false;
  for (final String banned in const <String>['\\', ':', ' ', '?', '#', '%']) {
    if (src.contains(banned)) return false;
  }
  final List<String> segments = src.split('/');
  for (final String segment in segments) {
    if (segment.isEmpty || segment == '.' || segment == '..') return false;
  }
  final String name = segments.last;
  final int dot = name.lastIndexOf('.');
  if (dot <= 0) return false;
  return dvRasterImageExtensions.contains(name.substring(dot + 1).toLowerCase());
}

/// A variant request, checked, or why it was refused.
class DVImageVariantRequest {
  const DVImageVariantRequest._({
    required this.src,
    required this.width,
    required this.quality,
    this.remote,
  });

  /// As asked: a path inside the site, or an address on an allowed host.
  final String src;
  final int width;
  final int quality;

  /// The address to fetch, when [src] is remote; null for a local image.
  final Uri? remote;

  /// Checks the query of a request to [dvImageEndpointPath].
  ///
  /// The width must be one of the configured set, because an arbitrary width
  /// is an arbitrary number of cache entries and an arbitrary amount of
  /// resizing somebody else can make the server do. A remote image must be on
  /// a host the application allowed, because an endpoint that fetches any
  /// address it is given is a way into whatever the server can reach.
  static ({DVImageVariantRequest? request, String? refusal}) parse(
    Map<String, String> query,
    DVImageVariants variants,
  ) {
    ({DVImageVariantRequest? request, String? refusal}) refuse(String why) =>
        (request: null, refusal: why);

    final int? width = int.tryParse(query['w'] ?? '');
    if (width == null || !variants.widths.contains(width)) {
      return refuse('w must be one of ${variants.widths.join(', ')}');
    }
    final String? quality = query['q'];
    if (quality != null && int.tryParse(quality) != variants.quality) {
      return refuse('q must be ${variants.quality}');
    }
    final String src = query['src'] ?? '';
    if (src.isEmpty) return refuse('src is required');

    final Uri? remote = _remote(src);
    if (remote != null) {
      if (remote.host.isEmpty || remote.userInfo.isNotEmpty) {
        return refuse('src is not an address this server will fetch');
      }
      if (!variants.allowsHost(remote.host)) {
        return refuse('${remote.host} is not in dartvel.images.remoteHosts');
      }
      return (
        request: DVImageVariantRequest._(
          src: src,
          width: width,
          quality: variants.quality,
          remote: remote,
        ),
        refusal: null,
      );
    }
    if (!dvIsLocalImagePath(src)) {
      return refuse('src must be the path of an image inside the site');
    }
    return (
      request: DVImageVariantRequest._(
        src: src,
        width: width,
        quality: variants.quality,
      ),
      refusal: null,
    );
  }
}

Uri? _remote(String src) {
  final String lower = src.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    return null;
  }
  return Uri.tryParse(src);
}
