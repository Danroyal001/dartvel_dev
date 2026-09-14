/// Who can open a preview, and that nothing indexes it.
///
/// Runs inside the preview's own process, in front of every handler. Every
/// response leaves with `X-Robots-Tag: noindex` -- a refusal, a script, the
/// robots file itself -- because indexing is opt-out everywhere else and a
/// preview outranking the product it previews is how traffic is lost.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../http/wintercg.dart';
import 'preview_config.dart';
import 'preview_lifecycle.dart';
import 'preview_secrets.dart';

/// What the running preview was deployed as, read from its environment.
final class DVPreviewRuntime {
  const DVPreviewRuntime({
    required this.name,
    required this.visibility,
    this.linkDigest,
    this.productionOrigin,
    this.schedules = const <String>{},
  });

  final String name;
  final DVPreviewVisibility visibility;

  /// SHA-256 of the link token, as lowercase hex.
  final String? linkDigest;

  /// Where canonical links point. Without it they are removed.
  final String? productionOrigin;

  /// Scheduled tasks declared to run in this preview.
  final Set<String> schedules;

  /// The preview this process is, or null when it is not one.
  ///
  /// Reads what [DVPreviewDeployment.variables] writes. A preview whose
  /// settings cannot be read is refused rather than served under a guess:
  /// the guess that looks like working is the one that admits everybody.
  static DVPreviewRuntime? fromEnvironment(Map<String, String> environment) {
    if (environment['DARTVEL_ENVIRONMENT'] != dvPreviewEnvironment) return null;
    final String? name = environment['DARTVEL_PREVIEW'];
    if (name == null || name.isEmpty) {
      throw const FormatException(
        'DARTVEL_ENVIRONMENT is preview and DARTVEL_PREVIEW names no preview',
      );
    }
    final String? rawVisibility = environment['DARTVEL_PREVIEW_VISIBILITY'];
    final DVPreviewVisibility visibility = DVPreviewVisibility.values.firstWhere(
      (DVPreviewVisibility v) => v.name == rawVisibility,
      orElse: () => throw FormatException(
        'DARTVEL_PREVIEW_VISIBILITY must be one of '
        '${DVPreviewVisibility.values.map((DVPreviewVisibility v) => v.name).join(' | ')}, '
        'got $rawVisibility',
      ),
    );
    final String? digest = environment['DARTVEL_PREVIEW_LINK_DIGEST'];
    if (visibility == DVPreviewVisibility.link &&
        (digest == null || !RegExp(r'^[0-9a-f]+$').hasMatch(digest))) {
      throw const FormatException(
        'a link preview needs DARTVEL_PREVIEW_LINK_DIGEST, the digest of its '
        'token; without it no link could be checked',
      );
    }
    final String rawSchedules = environment['DARTVEL_PREVIEW_SCHEDULES'] ?? '';
    return DVPreviewRuntime(
      name: name,
      visibility: visibility,
      linkDigest: digest,
      productionOrigin: environment['DARTVEL_PRODUCTION_ORIGIN'],
      schedules: <String>{
        for (final String s in rawSchedules.split(','))
          if (s.trim().isNotEmpty) s.trim(),
      },
    );
  }
}

/// Whether the person making a request belongs to the deployment's
/// organization.
enum DVPreviewMember { signedOut, member, notMember }

typedef DVPreviewMembership = FutureOr<DVPreviewMember> Function(Request request);

/// The gate in front of a preview.
final class DVPreviewAccess {
  DVPreviewAccess(
    this.runtime, {
    this.membership,
    this.signInPath = '/sign-in',
    Set<String> openPaths = const <String>{},
  }) : openPaths = Set<String>.unmodifiable(openPaths) {
    if (runtime.visibility == DVPreviewVisibility.members && membership == null) {
      throw ArgumentError.value(
        membership,
        'membership',
        'a members preview needs a way to ask whether a request belongs to '
            'the organization; without one it could only admit everybody',
      );
    }
  }

  final DVPreviewRuntime runtime;
  final DVPreviewMembership? membership;

  /// Where a signed-out request is sent. Reachable without membership.
  final String signInPath;

  /// Further path prefixes a members preview serves to anybody -- the auth
  /// endpoints the sign-in page calls.
  final Set<String> openPaths;

  static const String _robots = 'User-agent: *\nDisallow: /\n';

  Future<Response> handle(
    Request request,
    FutureOr<Response> Function(Request request) next,
  ) async {
    final Response response = await _decide(request, next);
    return _finish(request, response);
  }

  Future<Response> _decide(
    Request request,
    FutureOr<Response> Function(Request request) next,
  ) async {
    final String path = request.url.path.isEmpty ? '/' : request.url.path;
    if (path == '/robots.txt') return Response.text(_robots);

    switch (runtime.visibility) {
      case DVPreviewVisibility.public:
        return next(request);
      case DVPreviewVisibility.link:
        return _link(request, next);
      case DVPreviewVisibility.members:
        return _members(request, path, next);
    }
  }

  Future<Response> _link(
    Request request,
    FutureOr<Response> Function(Request request) next,
  ) async {
    final String? offered = request.url.queryParameters[dvPreviewLinkParameter];
    if (offered != null) {
      if (!_validToken(offered)) return _notFound();
      // The token leaves the address bar, the history and every Referer the
      // page sends, and lives in a cookie scripts cannot read.
      final Map<String, String> rest = <String, String>{
        ...request.url.queryParameters,
      }..remove(dvPreviewLinkParameter);
      final String location = Uri(
        path: request.url.path.isEmpty ? '/' : request.url.path,
        queryParameters: rest.isEmpty ? null : rest,
      ).toString();
      final Response redirect = Response.redirect(location);
      redirect.headers.set(
        'set-cookie',
        '$dvPreviewLinkParameter=$offered; Path=/; HttpOnly; Secure; SameSite=Lax',
      );
      return redirect;
    }
    final String? cookie = _cookie(request, dvPreviewLinkParameter);
    if (cookie == null || !_validToken(cookie)) return _notFound();
    return next(request);
  }

  Future<Response> _members(
    Request request,
    String path,
    FutureOr<Response> Function(Request request) next,
  ) async {
    bool under(String prefix) =>
        path == prefix || path.startsWith(prefix.endsWith('/') ? prefix : '$prefix/');
    if (under(signInPath) || openPaths.any(under)) return next(request);

    final DVPreviewMember who;
    try {
      who = await membership!(request);
    } catch (_) {
      // Unknown is not a member.
      return Response.text('membership could not be checked', status: 503);
    }
    switch (who) {
      case DVPreviewMember.member:
        return next(request);
      case DVPreviewMember.signedOut:
        final String back = request.url.hasQuery
            ? '$path?${request.url.query}'
            : path;
        return Response.redirect(
          Uri(path: signInPath, queryParameters: <String, String>{'return': back})
              .toString(),
        );
      case DVPreviewMember.notMember:
        return Response.text(
          'this preview is open to members of the deployment\'s organization',
          status: 403,
        );
    }
  }

  bool _validToken(String token) {
    final String? expected = runtime.linkDigest;
    if (expected == null || token.isEmpty) return false;
    final String actual = sha256.convert(utf8.encode(token)).toString();
    if (actual.length != expected.length) return false;
    int difference = 0;
    for (int i = 0; i < actual.length; i++) {
      difference |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return difference == 0;
  }

  static String? _cookie(Request request, String name) {
    for (final String header in request.headers.getAll('cookie')) {
      for (final String part in header.split(';')) {
        final int eq = part.indexOf('=');
        if (eq < 0) continue;
        if (part.substring(0, eq).trim() == name) {
          return part.substring(eq + 1).trim();
        }
      }
    }
    return null;
  }

  /// Not found rather than forbidden: a preview without its link is a URL
  /// that should look like nothing is there.
  static Response _notFound() => Response.text('not found', status: 404);

  Response _finish(Request request, Response response) {
    response.headers.set('x-robots-tag', 'noindex, nofollow');
    final String type = response.headers.get('content-type') ?? '';
    final Body? body = response.body;
    if (body == null || !type.toLowerCase().contains('text/html')) return response;
    final String path = request.url.path.isEmpty ? '/' : request.url.path;
    return Response(
      response.status,
      headers: response.headers,
      body: _rewriteHead(body.stream, path),
      isStream: response.isStream,
    );
  }

  /// Rewrites the canonical link in the document head, holding bytes back
  /// only until `</head>` has passed, so a page streamed shell-first still
  /// sends its body as it arrives.
  Stream<List<int>> _rewriteHead(Stream<List<int>> source, String path) async* {
    const int limit = 1 << 20;
    final BytesBuilder held = BytesBuilder(copy: false);
    bool passed = false;
    await for (final List<int> chunk in source) {
      if (passed) {
        yield chunk;
        continue;
      }
      held.add(chunk);
      final Uint8List bytes = held.toBytes();
      final int end = _headEnd(bytes);
      if (end >= 0) {
        passed = true;
        held.clear();
        yield utf8.encode(_canonical(utf8.decode(bytes.sublist(0, end), allowMalformed: true), path));
        if (end < bytes.length) yield bytes.sublist(end);
      } else if (bytes.length > limit) {
        // No head in the first megabyte is not an HTML page this can
        // rewrite; the noindex header still went out.
        passed = true;
        held.clear();
        yield bytes;
      }
    }
    if (!passed) {
      final Uint8List bytes = held.toBytes();
      if (bytes.isNotEmpty) {
        yield utf8.encode(_canonical(utf8.decode(bytes, allowMalformed: true), path));
      }
    }
  }

  /// The index just past `</head>`, or -1.
  static int _headEnd(Uint8List bytes) {
    const String marker = '</head>';
    outer:
    for (int i = 0; i + marker.length <= bytes.length; i++) {
      for (int j = 0; j < marker.length; j++) {
        int c = bytes[i + j];
        if (c >= 0x41 && c <= 0x5a) c += 0x20;
        if (c != marker.codeUnitAt(j)) continue outer;
      }
      return i + marker.length;
    }
    return -1;
  }

  String _canonical(String head, String path) {
    final String? origin = runtime.productionOrigin?.replaceAll(RegExp(r'/+$'), '');
    final String replacement = origin == null
        ? ''
        : '<link rel="canonical" href="${_escape('$origin$path')}">';
    final RegExp link = RegExp(
      r'''<link\b[^>]*\brel\s*=\s*["']?canonical["']?[^>]*>''',
      caseSensitive: false,
    );
    if (link.hasMatch(head)) {
      bool first = true;
      return head.replaceAllMapped(link, (_) {
        if (!first) return '';
        first = false;
        return replacement;
      });
    }
    if (origin == null) return head;
    final int close = head.toLowerCase().lastIndexOf('</head>');
    if (close < 0) return head;
    return '${head.substring(0, close)}$replacement${head.substring(close)}';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
