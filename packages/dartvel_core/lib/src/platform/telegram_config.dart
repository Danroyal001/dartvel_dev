/// Public Telegram Mini App metadata. Contains no server secrets.
class const DVTelegramConfig({
  final String botUsername = '',
  final String shortName = '',
  final List<String> requiredPermissions = const [],
}) {
  factory DVTelegramConfig.fromMap(Map<Object?, Object?> values) {
    if (values.keys.any(
      (key) => !const [
        'botUsername',
        'shortName',
        'requiredPermissions',
      ].contains(key),
    )) {
      throw const FormatException(
        'telegram accepts only botUsername, shortName and requiredPermissions; keep bot tokens on the server',
      );
    }
    final bot = values['botUsername'] ?? '';
    final name = values['shortName'] ?? '';
    final permissions = values['requiredPermissions'] ?? const [];
    if (bot is! String ||
        name is! String ||
        permissions is! List ||
        permissions.any(
          (value) =>
              value is! String || !const ['contact', 'write'].contains(value),
        )) {
      throw const FormatException('Invalid telegram configuration');
    }
    if (bot.isNotEmpty && !RegExp(r'^[A-Za-z0-9_]{5,32}$').hasMatch(bot) ||
        name.isNotEmpty && !RegExp(r'^[A-Za-z0-9_]{3,30}$').hasMatch(name)) {
      throw const FormatException(
        'Invalid Telegram bot username or short name',
      );
    }
    return DVTelegramConfig(
      botUsername: bot,
      shortName: name,
      requiredPermissions: List<String>.unmodifiable(
        permissions.cast<String>(),
      ),
    );
  }
  Map<String, Object?> toJson() => {
    'botUsername': botUsername,
    'shortName': shortName,
    'requiredPermissions': requiredPermissions,
  };
}
