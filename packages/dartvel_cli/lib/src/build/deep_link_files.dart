/// Where `dartvel.deepLinks` has to be written for a link to open the app.
///
/// Three places, one declaration. The site serves the two verification
/// documents under `/.well-known/`; the Android manifest carries an
/// `autoVerify` intent filter for the domains, or Android never fetches the
/// document; the iOS entitlements name the domains as `applinks:`, or iOS
/// never does. Each half without the others is a link that opens a browser,
/// which looks like a link that works.
///
/// And the deployed reality, checked by `dartvel doctor --target
/// android,ios`: a document behind a redirect, served as anything but JSON,
/// signed for a certificate the store does not use, or claiming fewer routes
/// than the application handles, is a failure nobody sees in a build.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVDeepLinks, dvDeepLinkCovers;
import 'package:path/path.dart' as p;

export 'package:dartvel_core/dartvel.dart' show DVDeepLinks;

const String _assetLinks = 'assetlinks.json';
const String _aasa = 'apple-app-site-association';

/// Writes the verification documents into the web build at [webDir] and
/// returns how many. Removes any this build no longer declares, so a domain
/// that stopped pointing at the application stops claiming it.
int dvWriteDeepLinkFiles({
  required String webDir,
  required DVDeepLinks? links,
  required List<String> routes,
  required Set<String> guarded,
}) {
  final Directory wellKnown = Directory(p.join(webDir, '.well-known'));
  final String? android = links?.assetLinks();
  final String? apple = links?.appleAppSiteAssociation(
    links.paths(routes: routes, guarded: guarded),
  );
  var written = 0;
  for (final (String name, String? body) in <(String, String?)>[
    (_assetLinks, android),
    (_aasa, apple),
  ]) {
    final File file = File(p.join(wellKnown.path, name));
    if (body == null) {
      if (file.existsSync()) file.deleteSync();
      continue;
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$body\n');
    written++;
  }
  return written;
}

const String _markStart = '            <!-- dartvel.deepLinks: begin -->';
const String _markEnd = '            <!-- dartvel.deepLinks: end -->';

/// [manifest] with an App Links intent filter for [links]'s domains inside
/// the main activity, or without one when [links] declares no Android app.
///
/// Marked, so a second build replaces the block rather than adding a second.
String dvAndroidDeepLinkManifest(
  String manifest,
  DVDeepLinks? links, {
  required List<String> paths,
}) {
  final RegExp block = RegExp(
    '\n${RegExp.escape(_markStart)}.*?${RegExp.escape(_markEnd)}',
    dotAll: true,
  );
  final String stripped = manifest.replaceAll(block, '');
  if (links == null ||
      links.domains.isEmpty ||
      links.androidPackage == null ||
      paths.isEmpty) {
    return stripped;
  }
  final int activity = stripped.indexOf('android:name=".MainActivity"');
  if (activity < 0) return stripped;
  final int close = stripped.indexOf('        </activity>', activity);
  if (close < 0) return stripped;

  final StringBuffer out = StringBuffer()
    ..writeln(_markStart)
    ..writeln('            <!-- App Links for dartvel.deepLinks. autoVerify is')
    ..writeln('                 what makes Android fetch assetlinks.json from')
    ..writeln('                 each host; without it a link opens a chooser')
    ..writeln('                 or the browser. -->')
    ..writeln('            <intent-filter android:autoVerify="true">')
    ..writeln(
      '                <action android:name="android.intent.action.VIEW"/>',
    )
    ..writeln(
      '                <category android:name="android.intent.category.DEFAULT"/>',
    )
    ..writeln(
      '                <category android:name="android.intent.category.BROWSABLE"/>',
    )
    ..writeln('                <data android:scheme="https"/>');
  for (final String domain in links.domains) {
    out.writeln('                <data android:host="$domain"/>');
  }
  for (final String path in paths) {
    out.writeln(
      path.contains('*')
          ? '                <data android:pathPattern="${path.replaceAll('*', '.*')}"/>'
          : '                <data android:path="$path"/>',
    );
  }
  out
    ..writeln('            </intent-filter>')
    ..write(_markEnd);
  return '${stripped.substring(0, close)}${out.toString()}\n'
      '${stripped.substring(close)}';
}

const String _domainsKey = 'com.apple.developer.associated-domains';

/// [entitlements] naming [links]'s domains as `applinks:`, or without the
/// key when [links] declares no iOS app.
String dvIosAssociatedDomains(String entitlements, DVDeepLinks? links) {
  final RegExp existing = RegExp(
    '\\n?[ \\t]*<key>${RegExp.escape(_domainsKey)}</key>\\s*<array>.*?</array>',
    dotAll: true,
  );
  final String stripped = entitlements.replaceAll(existing, '');
  if (links == null || links.domains.isEmpty || links.iosAppId == null) {
    return stripped;
  }
  final int close = stripped.lastIndexOf('</dict>');
  if (close < 0) return stripped;
  final StringBuffer out = StringBuffer()
    ..writeln('\t<key>$_domainsKey</key>')
    ..writeln('\t<array>');
  for (final String domain in links.domains) {
    out.writeln('\t\t<string>applinks:$domain</string>');
  }
  out.writeln('\t</array>');
  return '${stripped.substring(0, close).trimRight()}\n$out'
      '${stripped.substring(close)}';
}

/// The SHA-256 of the certificate `android/key.properties` signs with, as
/// keytool prints it, or null when there is no release signing configured
/// or keytool cannot read it.
Future<String?> dvAndroidSigningFingerprint(String root) async {
  final File properties = File(p.join(root, 'android', 'key.properties'));
  if (!properties.existsSync()) return null;
  final Map<String, String> values = <String, String>{
    for (final String line in properties.readAsLinesSync())
      if (line.contains('='))
        line.substring(0, line.indexOf('=')).trim(): line
            .substring(line.indexOf('=') + 1)
            .trim(),
  };
  final String? store = values['storeFile'];
  final String? alias = values['keyAlias'];
  final String? password = values['storePassword'];
  if (store == null || alias == null || password == null) return null;
  final String storePath = p.isAbsolute(store)
      ? store
      : p.join(root, 'android', 'app', store);
  try {
    final ProcessResult result = await Process.run('keytool', <String>[
      '-list',
      '-v',
      '-keystore',
      storePath,
      '-alias',
      alias,
      '-storepass',
      password,
    ]);
    if (result.exitCode != 0) return null;
    return RegExp(
      r'SHA256:\s*([0-9A-F:]{95})',
    ).firstMatch('${result.stdout}')?.group(1);
  } on ProcessException {
    return null;
  }
}

/// Checks the verification documents each of [links]'s domains serves.
///
/// [origin] maps a domain to where it is fetched from, `https://domain` in
/// use and a local server in a test. [signingFingerprint] is the certificate
/// the release build is signed by, compared against the served
/// fingerprints unless the application uses Play App Signing, where the
/// declared Play certificate is the one that matters. Returns one finding
/// per problem, each opening with its DV-LINKS code.
Future<List<String>> dvCheckDeepLinks({
  required DVDeepLinks links,
  required Set<String> targets,
  required List<String> routes,
  required Set<String> guarded,
  String? signingFingerprint,
  Uri Function(String domain)? origin,
}) async {
  final List<String> findings = <String>[];
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  try {
    for (final String domain in links.domains) {
      final Uri base = origin?.call(domain) ?? Uri.https(domain);
      if (targets.contains('android') && links.androidPackage != null) {
        final (Object?, String?) fetched = await _fetch(
          client,
          base.resolve('/.well-known/$_assetLinks'),
        );
        if (fetched.$2 != null) {
          findings.add(
            'DV-LINKS-002: $domain/.well-known/$_assetLinks '
            '${fetched.$2}',
          );
        } else {
          final List<String> served = _servedFingerprints(
            fetched.$1,
            links.androidPackage!,
          );
          if (served.isEmpty) {
            findings.add(
              'DV-LINKS-002: $domain/.well-known/$_assetLinks does '
              'not list ${links.androidPackage}.',
            );
          } else {
            final String? expected = links.playAppSigning
                ? (links.androidFingerprints.isEmpty
                      ? null
                      : links.androidFingerprints.first)
                : signingFingerprint;
            if (expected != null && !served.contains(expected)) {
              findings.add(
                'DV-LINKS-003: $domain/.well-known/$_assetLinks '
                'lists ${served.join(', ')} for ${links.androidPackage}, '
                'and the ${links.playAppSigning ? 'Play signing certificate' : 'release build is signed by a certificate'} '
                'with $expected. Android verifies the certificate the '
                'installed app was signed with, so every link opens the '
                'browser.',
              );
            }
          }
        }
      }
      if (targets.contains('ios') && links.iosAppId != null) {
        final (Object?, String?) fetched = await _fetch(
          client,
          base.resolve('/.well-known/$_aasa'),
        );
        if (fetched.$2 != null) {
          findings.add(
            'DV-LINKS-002: $domain/.well-known/$_aasa '
            '${fetched.$2}',
          );
        } else {
          final List<String> paths = _servedPaths(fetched.$1, links.iosAppId!);
          final List<String> uncovered = <String>[
            for (final String route in routes)
              if (!guarded.contains(route) &&
                  links.paths(routes: <String>[route]).isNotEmpty &&
                  !paths.any(
                    (String path) => dvDeepLinkCovers(
                      path,
                      links.paths(routes: <String>[route]).single,
                    ),
                  ))
                route,
          ];
          if (uncovered.isNotEmpty) {
            findings.add(
              'DV-LINKS-004: $domain/.well-known/$_aasa does not '
              'cover ${uncovered.join(', ')}, which the application handles. '
              'A link to one opens Safari. Rebuild and redeploy the site.',
            );
          }
        }
      }
    }
  } finally {
    client.close(force: true);
  }
  return findings;
}

/// The JSON at [uri], or why it is not usable.
Future<(Object?, String?)> _fetch(HttpClient client, Uri uri) async {
  try {
    final HttpClientRequest request = await client.getUrl(uri)
      ..followRedirects = false;
    final HttpClientResponse response = await request.close().timeout(
      const Duration(seconds: 15),
    );
    final String body = await utf8.decodeStream(response);
    if (response.isRedirect ||
        (response.statusCode >= 300 && response.statusCode < 400)) {
      return (
        null,
        'answers with a redirect (${response.statusCode} to '
            '${response.headers.value('location')}). The platforms do not '
            'follow redirects for this file.',
      );
    }
    if (response.statusCode != 200) {
      return (null, 'is not reachable: HTTP ${response.statusCode}.');
    }
    final String type = response.headers.contentType?.mimeType ?? '(none)';
    if (type != 'application/json') {
      return (null, 'is served as $type, not application/json.');
    }
    try {
      return (jsonDecode(body), null);
    } on FormatException {
      return (null, 'is served as JSON and does not parse as JSON.');
    }
  } on Object catch (error) {
    return (null, 'is not reachable: $error.');
  }
}

List<String> _servedFingerprints(Object? json, String package) => <String>[
  if (json is List)
    for (final Object? statement in json)
      if (statement is Map &&
          statement['target'] is Map &&
          (statement['target'] as Map)['package_name'] == package &&
          (statement['target'] as Map)['sha256_cert_fingerprints'] is List)
        for (final Object? f
            in (statement['target'] as Map)['sha256_cert_fingerprints'] as List)
          '$f'.toUpperCase(),
];

List<String> _servedPaths(Object? json, String appId) {
  final Object? applinks = json is Map ? json['applinks'] : null;
  final Object? details = applinks is Map ? applinks['details'] : null;
  if (details is! List) return const <String>[];
  return <String>[
    for (final Object? detail in details)
      if (detail is Map &&
          ((detail['appIDs'] is List &&
                  (detail['appIDs'] as List).contains(appId)) ||
              detail['appID'] == appId)) ...<String>[
        if (detail['components'] is List)
          for (final Object? component in detail['components'] as List)
            if (component is Map &&
                component['/'] is String &&
                component['exclude'] != true)
              component['/'] as String,
        if (detail['paths'] is List)
          for (final Object? path in detail['paths'] as List) '$path',
      ],
  ];
}

/// An entitlements property list with nothing in it, for a runner that has
/// none yet.
const String dvEmptyEntitlements = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
''';
