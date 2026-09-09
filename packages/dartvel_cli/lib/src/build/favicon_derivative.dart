/// The favicon a generated page wears, derived at build time.
///
/// A model can name one -- `@DVModel(favicon: '/icons/product.png')` -- and
/// the value used to go into the page as an href exactly as written. Whatever
/// that file happens to be is then what a browser downloads to fill a
/// 32-pixel square, on the first paint of every page the model generates. A
/// press shot at 512 is a few hundred kilobytes; the icon it replaces was
/// two.
///
/// So the build derives one: decode, resize to 32, re-encode, and name the
/// result after a hash of its own bytes. The hash is doing two jobs. It lets
/// the file be served immutable, because a changed icon is a changed name
/// rather than a stale cache entry somebody has to bust. And it makes two
/// models pointing at one source share a file instead of writing the same
/// pixels twice.
///
/// What this deliberately does not do is derive from a row's featured image.
/// The specification asks for that too, and it cannot happen here: the image
/// a row carries is a URL the database supplied, so deriving from it means
/// either fetching an arbitrary host during the build -- which makes the
/// build depend on somebody else's uptime and on a CDN free to serve
/// different bytes tomorrow -- or fetching it per request in the web server,
/// which is a round trip added to a page load to save a round trip. Both are
/// worse than the icon the page already has. A source this build can read off
/// its own disk is the part that is honestly derivable, and it is the part
/// that is derived.
library dartvel_cli.build.favicon_derivative;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'pwa_icons.dart';

/// The square a favicon is rendered into. One size, because one `<link
/// rel="icon">` is what a page carries and 32 is what every browser asks a
/// single-icon site for.
const int dvFaviconSize = 32;

/// A favicon derived from an image the project owns.
class DVDerivedFavicon {
  const DVDerivedFavicon({required this.href, required this.bytes});

  /// Where the file goes under the web root, and what the page points at.
  /// Content-addressed: `icons/favicon-<hash>.png`.
  final String href;

  /// The encoded PNG.
  final Uint8List bytes;
}

/// [source] resized to [size] and encoded, named after a hash of the result.
///
/// The alpha channel is dropped when nothing in the resized image uses it,
/// which is most icons and a quarter of the bytes. Resizing averages rather
/// than picks (see [dvResizeRgba]): a nearest-neighbour 512-to-32 of anything
/// with detail in it produces a plausible-looking icon made of whichever
/// pixels happened to land on the grid.
DVDerivedFavicon dvDeriveFavicon(DVRgbaImage source, {int size = dvFaviconSize}) {
  final DVRgbaImage small = dvResizeRgba(source, size, size);
  var opaque = true;
  for (var i = 3; i < small.pixels.length; i += 4) {
    if (small.pixels[i] != 255) {
      opaque = false;
      break;
    }
  }
  final Uint8List bytes = dvPngEncode(small, alpha: !opaque);
  // Half a SHA-256 is 64 bits of file name. A collision would serve one
  // model's icon on another's page, and at that width it will not happen
  // before the sun does something else.
  final String hash = sha256.convert(bytes).toString().substring(0, 16);
  return DVDerivedFavicon(href: 'icons/favicon-$hash.png', bytes: bytes);
}

/// The file [declared] names inside the project, or null when it names
/// something this build cannot read off its own disk.
///
/// Null for an absolute URL and for a data URI: neither is a file, and going
/// to fetch one would make the build depend on a host that is not part of it.
/// Null for anything with `..` in it, because a favicon path is a value out
/// of an annotation and a build should not write a file wherever an
/// annotation points.
File? dvFaviconSourceFile(String root, String declared) {
  final String value = declared.trim();
  if (value.isEmpty) return null;
  if (value.startsWith('//') || value.contains('://')) return null;
  if (value.startsWith('data:')) return null;
  if (value.split('/').contains('..')) return null;

  final String relative = value.startsWith('/') ? value.substring(1) : value;
  if (relative.isEmpty) return null;

  // web/ first: it is where a project's web assets live and what
  // `flutter build web` copies into the output, so it is the source rather
  // than the copy. build/web/ last, for a value naming something only the
  // build produced.
  for (final String base in <String>['web', '', p.join('build', 'web')]) {
    final File file = File(p.join(root, base, relative));
    if (file.existsSync()) return file;
  }
  return null;
}

/// The href a page should use for [declared], writing the derived icon under
/// [webRoot].
///
/// Returns [declared] unchanged when there is nothing to derive from -- a CDN
/// URL, an SVG or an ICO this decoder does not read, a file only the
/// deployment has. Passing it through is the point: rewriting it to something
/// this build invented would point every page at a 404, and dropping it would
/// silently undo a decision somebody made. Null in, null out, and no `icons/`
/// directory created for a project that declared no icon at all.
String? dvBuildFavicon({
  required String root,
  required Directory webRoot,
  required String? declared,
}) {
  if (declared == null || declared.trim().isEmpty) return null;
  final File? source = dvFaviconSourceFile(root, declared);
  if (source == null) return declared;

  final DVDerivedFavicon icon;
  try {
    icon = dvDeriveFavicon(dvPngDecode(source.readAsBytesSync()));
  } on DVPngError {
    return declared;
  } on FormatException {
    return declared;
  }

  final File target = File(p.join(webRoot.path, icon.href));
  // Written once. The name is the hash, so a file already there holds these
  // exact bytes and rewriting it would only cost the build time.
  if (!target.existsSync()) {
    target
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(icon.bytes);
  }
  return '/${icon.href}';
}
