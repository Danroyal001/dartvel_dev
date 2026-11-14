// The settings, read from the mount.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_meta_pixel/dartvel_meta_pixel.dart';
import 'package:test/test.dart';

void main() {
  setUp(DVSecrets.reset);
  tearDown(DVSecrets.reset);

  test('the mount\'s settings are read', () {
    final MetaPixelConfig config =
        MetaPixelConfig.fromModuleConfig(<String, Object?>{
      'pixelId': 1234567890,
      'consent': 'ads',
      'serverEvents': false,
      'testEventCode': 'TEST1',
      'excludePaths': <Object?>['/admin'],
    });
    expect(config.resolvedPixelId, '1234567890');
    expect(config.isConfigured, isTrue);
    expect(config.consentCategory, 'ads');
    expect(config.serverEvents, isFalse);
    expect(config.testEventCode, 'TEST1');
    expect(config.excludes('/admin/users'), isTrue);
    expect(config.excludes('/administrator'), isFalse);
  });

  test('with nothing set the defaults apply and it is not configured', () {
    const MetaPixelConfig config = MetaPixelConfig();
    expect(config.isConfigured, isFalse);
    expect(config.consentCategory, 'marketing');
    expect(config.serverEvents, isTrue);
    expect(config.excludes('/__studio/pages'), isTrue);
  });

  test('the server reads the pixel id from its environment', () {
    DVSecrets.configure(<String, String>{'META_PIXEL_ID': '9876543210'});
    expect(const MetaPixelConfig().resolvedPixelId, '9876543210');
    expect(const MetaPixelConfig(pixelId: '1234567890').resolvedPixelId,
        '1234567890');
  });

  test('something that is not a pixel id is not configured', () {
    expect(const MetaPixelConfig(pixelId: 'G-ABC').isConfigured, isFalse);
    expect(const MetaPixelConfig(pixelId: '').isConfigured, isFalse);
  });

  test('the access token in the mount is refused by name: it would be '
      'compiled into the client', () {
    expect(
      () => MetaPixelConfig.fromModuleConfig(
          <String, Object?>{'pixelId': '1234567890', 'accessToken': 'EAAB'}),
      throwsA(isA<ArgumentError>().having((ArgumentError e) => '${e.message}',
          'message', contains('META_CONVERSIONS_API_TOKEN'))),
    );
  });

  test('a setting it does not know is refused rather than ignored', () {
    expect(
      () => MetaPixelConfig.fromModuleConfig(
          <String, Object?>{'pixelID': '1234567890'}),
      throwsArgumentError,
    );
  });
}
