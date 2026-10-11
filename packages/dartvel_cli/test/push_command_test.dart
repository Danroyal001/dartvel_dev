import 'package:dartvel_cli/src/commands/push_command.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVWebPushKeyPair, dvWebPushBase64Decode;
import 'package:test/test.dart';

void main() {
  test('the pair is a P-256 key pair in the format push tooling exchanges', () {
    final ({String publicKey, String privateKey}) keys = dvGenerateVapidKeys();
    final List<int> publicBytes = dvWebPushBase64Decode(keys.publicKey);
    final List<int> privateBytes = dvWebPushBase64Decode(keys.privateKey);
    expect(publicBytes, hasLength(65));
    expect(publicBytes.first, 0x04);
    expect(privateBytes, hasLength(32));
    expect(keys.publicKey, isNot(contains('=')));
  });

  test('the public key is the one the private key derives', () {
    final ({String publicKey, String privateKey}) keys = dvGenerateVapidKeys();
    final DVWebPushKeyPair rebuilt = DVWebPushKeyPair.fromPrivateKey(
        dvWebPushBase64Decode(keys.privateKey));
    expect(rebuilt.publicKey, dvWebPushBase64Decode(keys.publicKey));
  });

  test('two runs give two different pairs', () {
    expect(dvGenerateVapidKeys().privateKey,
        isNot(dvGenerateVapidKeys().privateKey));
  });
}
