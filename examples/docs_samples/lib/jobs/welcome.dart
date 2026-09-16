// docs:start jobs-welcome
// lib/jobs/welcome.dart
// The generated job types, without Flutter, so a worker can run it.
import '../dartvel_client/jobs.g.dart';
import 'package:dartvel_core/dartvel.dart';

@DVJob(queue: 'mail', maxAttempts: 5, backoffSeconds: 60)
class _SendWelcomeEmail {
  final String userId;

  const _SendWelcomeEmail({required this.userId});
}

@DVJob.handler()
Future<void> _handleSendWelcomeEmail(SendWelcomeEmail job) =>
    sendWelcomeEmail(job.userId);
// docs:end

Future<void> sendWelcomeEmail(String userId) async {}
