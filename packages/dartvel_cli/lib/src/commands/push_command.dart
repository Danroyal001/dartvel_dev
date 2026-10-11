/// `dartvel push vapid-keys`: a VAPID key pair for Web Push.
///
/// The pair is the identity of the application server to browsers' push
/// services: a browser pins the public half when it subscribes, so the pair
/// is made once and kept. The private half is a Secret (`VAPID_PRIVATE_KEY`)
/// and is shown here once, on stdout, for the person to put where their
/// secrets live; the public half goes in pubspec as
/// `dartvel.push.web.vapidPublicKey`.
library;

import 'package:args/command_runner.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVWebPushKeyPair, dvWebPushBase64Encode;

import '../utils/logger.dart';

/// A fresh pair as the unpadded base64url strings push tooling exchanges.
({String publicKey, String privateKey}) dvGenerateVapidKeys() {
  final DVWebPushKeyPair pair = DVWebPushKeyPair.generate();
  return (
    publicKey: dvWebPushBase64Encode(pair.publicKey),
    privateKey: dvWebPushBase64Encode(pair.privateKey),
  );
}

class PushCommand extends Command<void> {
  @override
  final String name = 'push';

  @override
  final String description = 'Push notification setup: Web Push VAPID keys.';

  PushCommand() {
    addSubcommand(_VapidKeysCommand());
  }
}

class _VapidKeysCommand extends Command<void> {
  @override
  final String name = 'vapid-keys';

  @override
  final String description =
      'Generate a VAPID key pair for Web Push. Prints the private key once.';

  @override
  void run() {
    final ({String publicKey, String privateKey}) keys = dvGenerateVapidKeys();
    Logger.log('Public key (not secret; goes in pubspec.yaml):');
    Logger.log('  dartvel:');
    Logger.log('    push:');
    Logger.log('      web:');
    Logger.log('        vapidPublicKey: ${keys.publicKey}');
    Logger.log('');
    Logger.log('Private key (secret; shown once, keep it out of git):');
    Logger.log('  VAPID_PRIVATE_KEY=${keys.privateKey}');
    Logger.log('  VAPID_SUBJECT=mailto:you@example.com');
    Logger.log('');
    Logger.log('Keep this pair: browsers pin the public key when they '
        'subscribe, so replacing it ends every existing subscription.');
  }
}
