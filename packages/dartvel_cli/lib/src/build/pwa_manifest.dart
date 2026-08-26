/// The web app manifest, and whether a browser will offer to install it.
///
/// Installability fails silently. A manifest missing an icon size, or naming a
/// display mode the specification does not define, is served with a 200,
/// parsed without complaint, and simply never produces an install prompt.
/// There is no console error to find and nothing fails a build, so the checks
/// here run at build time instead.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// An icon entry. Square, because a maskable launcher icon is.
class DVPwaIcon {
  const DVPwaIcon({
    required this.src,
    required this.size,
    this.type = 'image/png',
    this.purpose,
  });

  final String src;

  /// The edge length in pixels. One number rather than a `WxH` string so a
  /// transposed or malformed pair cannot be written in the first place.
  final int size;

  final String type;

  /// `any`, `maskable`, or both. Null leaves it unset, which browsers read as
  /// `any`.
  final String? purpose;

  Map<String, Object?> toJson() => <String, Object?>{
        'src': src,
        'sizes': '${size}x$size',
        'type': type,
        if (purpose != null) 'purpose': purpose,
      };
}

/// The icon sizes a browser requires before it will offer an install.
///
/// Chrome wants one of at least 192 and one of at least 512 and rejects the
/// manifest for want of either.
const List<int> dvPwaRequiredIconSizes = <int>[192, 512];

/// The display modes the specification defines.
const Set<String> dvPwaDisplayModes = <String>{
  'fullscreen',
  'standalone',
  'minimal-ui',
  'browser',
};

const List<DVPwaIcon> _defaultIcons = <DVPwaIcon>[
  DVPwaIcon(src: 'icons/Icon-192.png', size: 192),
  DVPwaIcon(src: 'icons/Icon-512.png', size: 512),
  DVPwaIcon(src: 'icons/Icon-maskable-192.png', size: 192, purpose: 'maskable'),
  DVPwaIcon(src: 'icons/Icon-maskable-512.png', size: 512, purpose: 'maskable'),
];

/// A manifest for an application, with the defaults that make it installable.
Map<String, Object?> dvPwaManifest({
  required String name,
  String? shortName,
  String startUrl = '.',
  String display = 'standalone',
  String backgroundColor = '#FFFFFF',
  String themeColor = '#000000',
  String? description,
  List<DVPwaIcon> icons = _defaultIcons,
}) =>
    <String, Object?>{
      'name': name,
      // What a launcher shows under the icon. Omitting it is legal and gives
      // the truncated full name, which is worse than a sensible default.
      'short_name': shortName ?? name,
      'start_url': startUrl,
      'display': display,
      'background_color': backgroundColor,
      'theme_color': themeColor,
      if (description != null) 'description': description,
      'icons': icons.map((DVPwaIcon icon) => icon.toJson()).toList(),
    };

/// Why a manifest would or would not be installable.
class DVPwaInstallability {
  const DVPwaInstallability(this.problems);

  /// Every reason, not only the first: a build that fixes one and comes back
  /// for the next is a build run four times.
  final List<String> problems;

  bool get installable => problems.isEmpty;
}

/// Check [manifest] against the criteria browsers apply.
DVPwaInstallability dvPwaInstallability(Map<String, Object?> manifest) {
  final problems = <String>[];

  final name = manifest['name'];
  if (name is! String || name.trim().isEmpty) {
    problems.add('The manifest has no name, so nothing can label the install.');
  }

  final start = manifest['start_url'];
  if (start is! String || start.isEmpty) {
    problems.add('The manifest has no start_url, so there is nothing to open.');
  }

  final display = manifest['display'];
  if (display is! String || !dvPwaDisplayModes.contains(display)) {
    problems.add('display "$display" is not one of '
        '${dvPwaDisplayModes.join(', ')}. A browser ignores an unknown value '
        'and opens the app in a tab.');
  } else if (display == 'browser') {
    problems.add('display is "browser", which is legal and means the app '
        'opens in a tab rather than a window, so no install is offered.');
  }

  final icons = manifest['icons'];
  final sizes = <int>{};
  if (icons is List) {
    for (final Object? icon in icons) {
      if (icon is! Map) continue;
      final declared = icon['sizes'];
      if (declared is! String) continue;
      for (final String pair in declared.split(RegExp(r'\s+'))) {
        final edge = int.tryParse(pair.split('x').first);
        if (edge != null) sizes.add(edge);
      }
    }
  }
  for (final int required in dvPwaRequiredIconSizes) {
    if (!sizes.any((int size) => size >= required)) {
      problems.add('No icon of at least ${required}px. A browser rejects the '
          'whole manifest for want of one and shows no error.');
    }
  }

  return DVPwaInstallability(problems);
}

/// Link the manifest from a page's head, if it does not already.
///
/// Flutter's own web template ships a manifest link. Adding a second gives two
/// manifests and leaves which one wins up to the browser, so a page that
/// already has one is returned untouched.
String dvPwaLinkManifest(String html, {String href = 'manifest.json'}) {
  if (RegExp(r'''rel\s*=\s*["']?manifest''').hasMatch(html)) return html;
  final head = html.indexOf('</head>');
  // No head to put it in. Returning the page unchanged is better than
  // inventing structure around someone's template.
  if (head < 0) return html;
  return '${html.substring(0, head)}  <link rel="manifest" href="$href">\n'
      '${html.substring(head)}';
}

/// What writing the manifest into a built web app did.
class DVPwaWriteResult {
  const DVPwaWriteResult({
    required this.wrote,
    required this.linked,
    required this.problems,
  });

  /// Whether manifest.json was written.
  final bool wrote;

  /// Whether a link had to be added to index.html. False when one was already
  /// there, which is the normal case for Flutter's own template.
  final bool linked;

  /// Installability problems found. Reported rather than thrown: a manifest a
  /// browser will not install is still a web app that runs.
  final List<String> problems;
}

/// Write the manifest into a built web application and link it from the page.
///
/// Overwrites Flutter's default manifest deliberately. That one is generated
/// from the template with the project's package name and no configuration, so
/// leaving it in place would ship an app named `dartvel_example` to every user
/// who set `dartvel.pwa.name`.
DVPwaWriteResult dvPwaWrite({
  required String webBuildDir,
  required Map<String, Object?> manifest,
}) {
  final directory = Directory(webBuildDir);
  if (!directory.existsSync()) {
    return const DVPwaWriteResult(
      wrote: false,
      linked: false,
      problems: <String>['There is no web build to write a manifest into.'],
    );
  }

  File(p.join(webBuildDir, 'manifest.json'))
      .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(manifest)}\n');

  var linked = false;
  final index = File(p.join(webBuildDir, 'index.html'));
  if (index.existsSync()) {
    final before = index.readAsStringSync();
    final after = dvPwaLinkManifest(before);
    if (after != before) {
      index.writeAsStringSync(after);
      linked = true;
    }
  }

  return DVPwaWriteResult(
    wrote: true,
    linked: linked,
    problems: dvPwaInstallability(manifest).problems,
  );
}
