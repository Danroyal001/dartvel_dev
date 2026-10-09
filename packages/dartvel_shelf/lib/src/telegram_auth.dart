/// Server-only Telegram Mini App authentication. Never import into a client.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart' show AuthProvider, AuthUser;

/// Checks Telegram's HMAC and freshness before trusting user fields.
class const DVTelegramInitDataValidator({
  required final String botToken,
  final Duration maxAge = const Duration(minutes: 5),
}) {
  factory DVTelegramInitDataValidator.fromEnvironment({
    String variable = 'TELEGRAM_BOT_TOKEN',
    Duration maxAge = const Duration(minutes: 5),
  }) {
    final token = Platform.environment[variable];
    if (token == null || token.isEmpty)
      throw StateError('$variable must be set on the server');
    return DVTelegramInitDataValidator(botToken: token, maxAge: maxAge);
  }

  AuthUser validate(String initData, {DateTime? now}) {
    if (botToken.isEmpty || maxAge <= .zero || initData.length > 16384) {
      throw const FormatException('Invalid Telegram credentials');
    }
    final all = Uri.splitQueryString(initData);
    if (Uri(query: initData).queryParametersAll.values
        .any((v) => v.length != 1)) {
      throw const FormatException('Duplicate Telegram field');
    }
    final hash = all.remove('hash');
    if (hash == null || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid Telegram hash');
    }
    // HMAC includes signature; Ed25519 third-party validation excludes it.
    final keys = all.keys.toList()..sort();
    final secret = Hmac(
      sha256,
      utf8.encode('WebAppData'),
    ).convert(utf8.encode(botToken));
    final expected = Hmac(
      sha256,
      secret.bytes,
    ).convert(utf8.encode(keys.map((k) => '$k=${all[k]}').join('\n'))).bytes;
    var different = 0;
    for (var i = 0; i < expected.length; i++) {
      different |=
          expected[i] ^ int.parse(hash.substring(i * 2, i * 2 + 2), radix: 16);
    }
    if (different != 0)
      throw const FormatException('Invalid Telegram signature');
    final timestamp = int.tryParse(all['auth_date'] ?? '');
    final seconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    if (timestamp == null ||
        timestamp > seconds ||
        seconds - timestamp > maxAge.inSeconds) {
      throw const FormatException('Expired Telegram credentials');
    }
    final decoded = jsonDecode(all['user'] ?? '');
    if (decoded is! Map<String, dynamic> ||
        decoded['id'] is! int ||
        (decoded['id'] as int) <= 0 ||
        decoded['first_name'] is! String) {
      throw const FormatException('Invalid Telegram user');
    }
    return AuthUser(
      id: 'telegram:${decoded['id']}',
      email: '',
      name: [
        decoded['first_name'],
        decoded['last_name'],
      ].whereType<String>().join(' '),
      metadata: Map<String, Object?>.unmodifiable(decoded),
    );
  }
}

/// Provider for the existing Dartvel session endpoint. Raw initData is the
/// password; email is ignored. Session state belongs to the session layer.
class const DVTelegramAuthProvider({
  required final DVTelegramInitDataValidator validator,
}) implements AuthProvider {
  @override
  Future<AuthUser?> signIn(String email, String password) async =>
      validator.validate(password);
  @override
  Future<AuthUser?> signUp(String email, String password, {String? name}) =>
      signIn(email, password);
  @override
  Future<void> signOut() async {}
  @override
  Future<AuthUser?> currentUser() async => null;
  @override
  Stream<AuthUser?> get authStateChanges => const Stream.empty();
}
