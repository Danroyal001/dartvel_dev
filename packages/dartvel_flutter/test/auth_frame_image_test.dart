import 'package:dartvel_flutter/src/auth/auth_image_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// dartvel.pwa.icon names a file in the project's web/ folder. On the web
/// that file is served from the site root, not from the asset bundle, so
/// loading it as an asset asked for /assets/web/icon.png, got a 404, and the
/// sign-in page's brand panel lost its icon without a word.
void main() {
  test('a web/ file is fetched from where the site serves it', () {
    final DVAuthImageSource source = dvAuthImageSource('web/icon.png', web: true);
    expect(source.network, isTrue);
    expect(source.location, 'icon.png');
  });

  test('nested web/ files keep their folder', () {
    expect(dvAuthImageSource('web/icons/Icon-192.png', web: true).location,
        'icons/Icon-192.png');
  });

  test('declared assets stay assets on the web', () {
    final DVAuthImageSource source = dvAuthImageSource('assets/brand.png', web: true);
    expect(source.network, isFalse);
    expect(source.location, 'assets/brand.png');
  });

  test('off the web every image is an asset', () {
    final DVAuthImageSource source = dvAuthImageSource('web/icon.png', web: false);
    expect(source.network, isFalse);
    expect(source.location, 'web/icon.png');
  });
}
