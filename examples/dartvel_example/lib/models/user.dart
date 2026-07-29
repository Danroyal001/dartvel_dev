import 'package:dartvel_core/dartvel.dart';

@DVModel(generatePublicPages: true)
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
