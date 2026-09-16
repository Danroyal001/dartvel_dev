// docs:start backend-background
// lib/backend/functions/signup.post.dart
import 'package:dartvel_core/dartvel.dart';

import '../../dartvel_client/jobs.g.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _signup(String userId) async {
  // The response goes out now. A worker sends the email.
  await SendWelcomeEmail(userId: userId).dispatch();
  return <String, Object?>{'queued': true};
}
// docs:end
