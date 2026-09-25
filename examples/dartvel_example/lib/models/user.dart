import 'package:dartvel_core/dartvel.dart';

// The favicon these pages wear. Points at a file the example actually
// ships, because a page wearing an icon that 404s looks exactly like a
// page wearing none.
// Each user is the person their row belongs to, and an account is kept for
// as long as it exists -- deliberately, which is the declaration
// DV-PRIVACY-002 asks for rather than a retention nobody decided.
@DVModel(
  generatePublicPages: true,
  favicon: '/favicon.png',
  subject: DVSubject.self,
  retain: DVRetention.indefinite,
)
@pragma('vm:entry-point')
class const _User({
  required final String slug,
  required final String name,
  required final String email,
  required final bool published,
  @DVModel.sensitiveField() required final String recoveryToken,
});
