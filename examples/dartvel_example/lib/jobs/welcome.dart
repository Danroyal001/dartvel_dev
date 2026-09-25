import 'package:dartvel_example/dartvel_client/dartvel_client.dart';

@DVJob(queue: 'mail', maxAttempts: 5, backoffSeconds: 60)
@pragma('vm:entry-point')
class const _SendWelcomeEmail({required final String userId});

@DVJob.handler()
@pragma('vm:entry-point')
Future<void> _handleSendWelcomeEmail(SendWelcomeEmail job) async =>
    DV.log('welcome mail for ${job.userId}');
