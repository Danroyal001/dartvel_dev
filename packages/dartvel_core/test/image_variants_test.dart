// Image variants: the widths Dartvel resizes an image to, the one address a
// variant is asked for by, and what a server refuses to fetch.
//
// NextFaster serves every image at one of a fixed set of widths and its links
// prefetch the one the visitor's screen will use. The widget, the link
// prefetch and the server all have to agree on that address -- a prefetch of
// a slightly different URL is a second download, not a cache hit -- so it is
// worked out here, once, and each of them calls this.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('a width snaps to the configured set', () {
    const DVImageVariants variants = DVImageVariants();

    test('to the smallest width that covers it', () {
      expect(variants.snap(300), 384);
      expect(variants.snap(640), 640);
      expect(variants.snap(641), 750);
    });

    test('and never past the largest', () {
      expect(variants.snap(5000), 3840);
    });

    test('a zero-width layout still asks for something real', () {
      expect(variants.snap(0), 16);
    });
  });

  group('the address of a variant', () {
    const DVImageVariants built = DVImageVariants(
      endpoint: true,
      remoteHosts: <String>['cdn.example.com'],
      assetWidths: <String, int>{'assets/assets/hero.png': 1600},
    );

    test('an asset the build resized is one of its written files', () {
      expect(built.variantUrl('assets/assets/hero.png', 320),
          'assets/_dartvel/img/384/assets/assets/hero.png');
    });

    test('a denser screen asks for a larger variant', () {
      // The same 320-pixel-wide slot at a device pixel ratio of 2.
      expect(built.variantUrl('assets/assets/hero.png', 640),
          'assets/_dartvel/img/640/assets/assets/hero.png');
    });

    test('never larger than the source: the original is used instead', () {
      // 2000 snaps to 2048, which is past the 1600 the source has. Nothing
      // was written for it, and an upscaled copy would be bigger and no
      // sharper.
      expect(built.variantUrl('assets/assets/hero.png', 2000), isNull);
    });

    test('an allowed remote image goes through the server', () {
      expect(
        built.variantUrl('https://cdn.example.com/a.jpg', 700),
        '_dartvel/image?src=https%3A%2F%2Fcdn.example.com%2Fa.jpg&w=750&q=75',
      );
    });

    test('a host nobody allowed is fetched as it is', () {
      expect(built.variantUrl('https://elsewhere.example.org/a.jpg', 700),
          isNull);
    });

    test('with no server there is nothing to ask for a remote variant', () {
      const DVImageVariants static = DVImageVariants(
        remoteHosts: <String>['cdn.example.com'],
        assetWidths: <String, int>{'assets/assets/hero.png': 1600},
      );
      expect(static.variantUrl('https://cdn.example.com/a.jpg', 700), isNull);
      expect(static.variantUrl('assets/assets/hero.png', 320),
          'assets/_dartvel/img/384/assets/assets/hero.png');
    });

    test('an application that configured nothing gets no variants at all', () {
      const DVImageVariants none = DVImageVariants();
      expect(none.isActive, isFalse);
      expect(none.variantUrl('assets/assets/hero.png', 320), isNull);
    });
  });

  group('a host is allowed', () {
    const DVImageVariants variants = DVImageVariants(
      remoteHosts: <String>['cdn.example.com', '*.images.example.net'],
    );

    test('by name', () {
      expect(variants.allowsHost('cdn.example.com'), isTrue);
      expect(variants.allowsHost('CDN.Example.com'), isTrue);
    });

    test('by a wildcard for its subdomains, not the name itself', () {
      expect(variants.allowsHost('a.images.example.net'), isTrue);
      expect(variants.allowsHost('images.example.net'), isFalse);
    });

    test('and not by resemblance', () {
      expect(variants.allowsHost('evilcdn.example.com'), isFalse);
      expect(variants.allowsHost('cdn.example.com.evil.org'), isFalse);
      expect(variants.allowsHost('x-images.example.net'), isFalse);
    });
  });

  group('a request the server is asked', () {
    const DVImageVariants variants = DVImageVariants(
      endpoint: true,
      remoteHosts: <String>['cdn.example.com'],
    );

    DVImageVariantRequest? ok(Map<String, String> query) =>
        DVImageVariantRequest.parse(query, variants).request;
    String? refusal(Map<String, String> query) =>
        DVImageVariantRequest.parse(query, variants).refusal;

    test('for a local image at a configured width is accepted', () {
      final DVImageVariantRequest? request =
          ok(<String, String>{'src': 'assets/assets/hero.png', 'w': '640'});
      expect(request?.src, 'assets/assets/hero.png');
      expect(request?.width, 640);
      expect(request?.quality, 75);
      expect(request?.remote, isNull);
    });

    test('for a width outside the set is refused', () {
      // An arbitrary width is an arbitrary number of cache entries, and an
      // arbitrary amount of resizing somebody else can make the server do.
      expect(refusal(<String, String>{'src': 'assets/a.png', 'w': '641'}),
          isNotNull);
      expect(refusal(<String, String>{'src': 'assets/a.png', 'w': 'big'}),
          isNotNull);
      expect(refusal(<String, String>{'src': 'assets/a.png'}), isNotNull);
    });

    test('for a quality other than the configured one is refused', () {
      expect(
          refusal(<String, String>{'src': 'assets/a.png', 'w': '640', 'q': '1'}),
          isNotNull);
      expect(
          ok(<String, String>{'src': 'assets/a.png', 'w': '640', 'q': '75'}),
          isNotNull);
    });

    test('for anything outside the site is refused', () {
      for (final String src in <String>[
        '../secret.png',
        'assets/../../secret.png',
        'assets/./a.png',
        'assets//a.png',
        '/etc/passwd.png',
        r'assets\..\secret.png',
        'C:/secret.png',
        'file:///etc/passwd.png',
        'assets/a.png\u0000.png',
        '',
      ]) {
        expect(refusal(<String, String>{'src': src, 'w': '640'}), isNotNull,
            reason: src);
      }
    });

    test('for something that is not an image is refused', () {
      expect(refusal(<String, String>{'src': 'main.dart.js', 'w': '640'}),
          isNotNull);
      expect(
          refusal(<String, String>{'src': 'dartvel_routes.json', 'w': '640'}),
          isNotNull);
    });

    test('for a host nobody allowed is refused before anything is fetched', () {
      // An endpoint that fetches any URL it is given is a way into whatever
      // the server can reach: its own metadata service, its own admin.
      expect(
        refusal(<String, String>{
          'src': 'https://169.254.169.254/latest/meta-data.png',
          'w': '640',
        }),
        isNotNull,
      );
      expect(
        refusal(<String, String>{
          'src': 'https://evil.example.org/a.png',
          'w': '640',
        }),
        isNotNull,
      );
    });

    test('for an allowed host with credentials or an odd scheme is refused',
        () {
      expect(
        refusal(<String, String>{
          'src': 'https://user:pw@cdn.example.com/a.png',
          'w': '640',
        }),
        isNotNull,
      );
      expect(
        refusal(<String, String>{'src': 'ftp://cdn.example.com/a.png', 'w': '640'}),
        isNotNull,
      );
    });

    test('for an allowed host is accepted, with its address', () {
      final DVImageVariantRequest? request = ok(<String, String>{
        'src': 'https://cdn.example.com/photos/a.jpg',
        'w': '1080',
      });
      expect(request?.remote, Uri.parse('https://cdn.example.com/photos/a.jpg'));
    });
  });

  group('dartvel.images in pubspec.yaml', () {
    test('sets the widths, the quality and the hosts', () {
      final ({DVImageVariants variants, List<String> problems}) parsed =
          DVImageVariants.parse(<String, Object?>{
        'widths': <Object?>[1200, 640, 640, 320],
        'quality': 60,
        'remoteHosts': <Object?>['cdn.example.com'],
      });
      expect(parsed.problems, isEmpty);
      expect(parsed.variants.widths, <int>[320, 640, 1200],
          reason: 'sorted and deduplicated, so snapping can walk them');
      expect(parsed.variants.quality, 60);
      expect(parsed.variants.remoteHosts, <String>['cdn.example.com']);
    });

    test('says what it did not accept, and keeps the default', () {
      final ({DVImageVariants variants, List<String> problems}) parsed =
          DVImageVariants.parse(<String, Object?>{
        'quality': 0,
        'widths': <Object?>[640, -1, 'wide'],
        'remoteHosts': 'cdn.example.com',
      });
      expect(parsed.problems, hasLength(3));
      expect(parsed.variants.quality, 75);
      expect(parsed.variants.widths, <int>[640]);
      expect(parsed.variants.remoteHosts, isEmpty);
    });

    test('with no section, the defaults', () {
      final ({DVImageVariants variants, List<String> problems}) parsed =
          DVImageVariants.parse(null);
      expect(parsed.problems, isEmpty);
      expect(parsed.variants.widths, dvDefaultImageWidths);
    });
  });

  test('what the build hands the app survives the trip', () {
    const DVImageVariants built = DVImageVariants(
      widths: <int>[320, 640],
      quality: 60,
      endpoint: true,
      remoteHosts: <String>['cdn.example.com'],
      assetWidths: <String, int>{'assets/assets/hero.png': 1600},
    );
    final DVImageVariants back = DVImageVariants.fromJson(built.toJson());
    expect(back.widths, built.widths);
    expect(back.quality, 60);
    expect(back.endpoint, isTrue);
    expect(back.remoteHosts, built.remoteHosts);
    expect(back.assetWidths, built.assetWidths);
    expect(DVImageVariants.fromJson('not json').isActive, isFalse);
  });

  test('and survives being a --dart-define, which is split on commas', () {
    // The build hands the variants over as base64url so the value has no
    // comma for the flutter tool to split a JSON object at.
    const DVImageVariants built = DVImageVariants(
      widths: <int>[320, 640],
      endpoint: true,
      assetWidths: <String, int>{'assets/assets/hero.png': 1600},
    );
    final String define = built.toDartDefine();
    expect(define, isNot(contains(',')));
    final DVImageVariants back = DVImageVariants.fromJson(define);
    expect(back.widths, <int>[320, 640]);
    expect(back.endpoint, isTrue);
    expect(back.assetWidths, built.assetWidths);
  });
}
