// dartvel.deepLinks: the two verification documents and the patterns in them.
//
// Android App Links and iOS Universal Links are only links once the platform
// has fetched a JSON file from the site and found the application in it.
// Both files are functions of the route index and the application ids, so
// the build writes them; these hold what goes in them.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String _fingerprint =
    '14:6D:E9:83:C5:73:06:50:D8:EE:B9:95:2F:34:FC:64:16:A0:83:42:E6:1D:BE:A8:8A:04:96:B2:3F:CF:44:E5';

DVDeepLinkConfig parse(Map<String, Object?> yaml) =>
    DVDeepLinkConfig.parse(yaml)!;

void main() {
  group('reading dartvel.deepLinks', () {
    test('nothing declared is no deep links', () {
      expect(DVDeepLinkConfig.parse(null), isNull);
    });

    test('every key the section documents', () {
      final DVDeepLinkConfig links = parse(<String, Object?>{
        'domains': <String>['example.com', 'www.example.com'],
        'android': <String, Object?>{
          'package': 'com.example.app',
          'fingerprints': <String>[_fingerprint],
        },
        'ios': <String, Object?>{'appId': 'ABCDE12345.com.example.app'},
        'exclude': <String>['/admin/**'],
      });
      expect(links.domains, <String>['example.com', 'www.example.com']);
      expect(links.androidPackage, 'com.example.app');
      expect(links.androidFingerprints, <String>[_fingerprint]);
      expect(links.iosAppId, 'ABCDE12345.com.example.app');
      expect(links.exclude, <String>['/admin/**']);
    });

    test('playAppSigning reads the Play signing certificate it names', () {
      final DVDeepLinkConfig links = parse(<String, Object?>{
        'domains': <String>['example.com'],
        'android': <String, Object?>{
          'package': 'com.example.app',
          'fingerprints': 'playAppSigning',
          'playSigningCertificate': _fingerprint,
        },
      });
      expect(links.playAppSigning, isTrue);
      expect(links.androidFingerprints, <String>[_fingerprint]);
      expect(links.missingIdentifiers(<String>{'android'}), isEmpty);

      final DVDeepLinkConfig unnamed = parse(<String, Object?>{
        'domains': <String>['example.com'],
        'android': <String, Object?>{
          'package': 'com.example.app',
          'fingerprints': 'playAppSigning',
        },
      });
      expect(
        unnamed.missingIdentifiers(<String>{'android'}).single,
        contains('playSigningCertificate'),
      );
    });

    test('a misspelt key is refused rather than ignored', () {
      expect(
        () => parse(<String, Object?>{
          'domains': <String>['example.com'],
          'andriod': <String, Object?>{'package': 'x'},
        }),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            contains('andriod'),
          ),
        ),
      );
    });

    test('a domain written as a URL is refused', () {
      expect(
        () => parse(<String, Object?>{
          'domains': <String>['https://example.com/'],
        }),
        throwsFormatException,
      );
    });

    test('a fingerprint that is not a SHA-256 is refused', () {
      expect(
        () => parse(<String, Object?>{
          'domains': <String>['example.com'],
          'android': <String, Object?>{
            'package': 'com.example.app',
            'fingerprints': <String>['AB:CD'],
          },
        }),
        throwsFormatException,
      );
    });
  });

  group('DV-LINKS-001', () {
    test('domains with no application id for a target the app builds', () {
      final DVDeepLinkConfig links = parse(<String, Object?>{
        'domains': <String>['example.com'],
        'ios': <String, Object?>{'appId': 'ABCDE12345.com.example.app'},
      });
      final List<String> errors = links.missingIdentifiers(<String>{
        'android',
        'ios',
        'web',
      });
      expect(errors, hasLength(1));
      expect(errors.single, contains('DV-LINKS-001'));
      expect(errors.single, contains('android'));
      expect(links.missingIdentifiers(<String>{'ios', 'web'}), isEmpty);
    });

    test('android without fingerprints is missing its identity too', () {
      final DVDeepLinkConfig links = parse(<String, Object?>{
        'domains': <String>['example.com'],
        'android': <String, Object?>{'package': 'com.example.app'},
      });
      expect(
        links.missingIdentifiers(<String>{'android'}).single,
        contains('fingerprints'),
      );
    });
  });

  group('the patterns', () {
    final DVDeepLinkConfig links = parse(<String, Object?>{
      'domains': <String>['example.com'],
      'exclude': <String>['/admin/**'],
    });

    test('come from the route index, minus guarded and excluded routes', () {
      final List<String> paths = links.paths(
        routes: <String>[
          '/',
          '/team',
          '/team/:member',
          '/admin/reports',
          '/account',
          '/docs/*rest',
        ],
        guarded: <String>{'/account'},
      );
      expect(paths, <String>['/', '/team', '/team/*', '/docs/*']);
    });

    test('a guarded parameterised route is left out too', () {
      expect(
        links.paths(
          routes: <String>['/orders/:id'],
          guarded: <String>{'/orders/:id'},
        ),
        isEmpty,
      );
    });
  });

  group('the documents', () {
    final DVDeepLinkConfig links = parse(<String, Object?>{
      'domains': <String>['example.com'],
      'android': <String, Object?>{
        'package': 'com.example.app',
        'fingerprints': <String>[_fingerprint],
      },
      'ios': <String, Object?>{'appId': 'ABCDE12345.com.example.app'},
    });

    test('assetlinks.json names the package and its fingerprints', () {
      final Object? json = jsonDecode(links.assetLinks()!);
      expect(json, <Object?>[
        <String, Object?>{
          'relation': <String>['delegate_permission/common.handle_all_urls'],
          'target': <String, Object?>{
            'namespace': 'android_app',
            'package_name': 'com.example.app',
            'sha256_cert_fingerprints': <String>[_fingerprint],
          },
        },
      ]);
    });

    test('apple-app-site-association lists the app and its paths', () {
      final Object? json = jsonDecode(
        links.appleAppSiteAssociation(<String>['/', '/team/*'])!,
      );
      expect(json, <String, Object?>{
        'applinks': <String, Object?>{
          'details': <Object?>[
            <String, Object?>{
              'appIDs': <String>['ABCDE12345.com.example.app'],
              'components': <Object?>[
                <String, Object?>{'/': '/'},
                <String, Object?>{'/': '/team/*'},
              ],
            },
          ],
        },
      });
    });

    test('no document for a platform with no identity', () {
      final DVDeepLinkConfig webOnly = parse(<String, Object?>{
        'domains': <String>['example.com'],
      });
      expect(webOnly.assetLinks(), isNull);
      expect(webOnly.appleAppSiteAssociation(<String>['/']), isNull);
    });
  });

  test('a served path covers a route the way the platform matches it', () {
    expect(dvDeepLinkCovers('/team/*', '/team/ada'), isTrue);
    expect(dvDeepLinkCovers('/team/*', '/teams'), isFalse);
    expect(dvDeepLinkCovers('/', '/'), isTrue);
    expect(dvDeepLinkCovers('/about', '/about/more'), isFalse);
  });
}
