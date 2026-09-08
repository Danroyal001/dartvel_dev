import 'package:dartvel_core/dartvel.dart';

// The favicon these pages wear. Points at a file the example actually
// ships, because a page wearing an icon that 404s looks exactly like a
// page wearing none.
@DVModel(generatePublicPages: true, favicon: '/favicon.png')
@pragma('vm:entry-point')
class _User {
  final String slug;
  final String name;
  final String email;
  final bool published;
  @DVModel.sensitiveField()
  final String recoveryToken;

  const _User({
    required this.slug,
    required this.name,
    required this.email,
    required this.published,
    required this.recoveryToken,
  });
}
