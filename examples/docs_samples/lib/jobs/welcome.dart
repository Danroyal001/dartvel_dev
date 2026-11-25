// docs:start jobs-welcome
// lib/jobs/welcome.dart
// The generated job types, without Flutter, so a worker can run it.
import 'package:dartvel_core/dartvel.dart';

import '../dartvel_client/jobs.g.dart';

@DVJob(queue: 'mail', maxAttempts: 5, backoffSeconds: 60)
class const _SendWelcomeEmail({required final String userId});

@DVJob.handler()
Future<void> _handleSendWelcomeEmail(SendWelcomeEmail job) =>
    sendWelcomeEmail(job.userId);
// docs:end

Future<void> sendWelcomeEmail(String userId) async {}
