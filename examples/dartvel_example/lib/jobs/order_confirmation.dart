import 'package:dartvel_example/dartvel_client/dartvel_client.dart';

/// The receipt, sent through the queue rather than on the tap: a mail server
/// that is down retries later instead of failing the checkout.
@DVJob(queue: 'orders', maxAttempts: 5, backoffSeconds: 30)
@pragma('vm:entry-point')
class const _SendOrderConfirmation({
  required final String orderId,
  required final String email,
  required final String summary,
  required final int totalCents,
});

@DVJob.handler()
@pragma('vm:entry-point')
Future<void> _handleSendOrderConfirmation(SendOrderConfirmation job) =>
    DV.Notifications.mail.send(
      DVMailMessage(
        from: const DVMailAddress(
          'orders@oakline.coffee',
          name: 'Oakline Coffee',
        ),
        to: <DVMailAddress>[DVMailAddress(job.email)],
        subject: 'Your order ${job.orderId}',
        text:
            'Thanks for your order: ${job.summary}. '
            'Total \$${(job.totalCents / 100).toStringAsFixed(2)}. '
            'We roast on Tuesdays and Fridays and will tell you when it ships.',
      ),
    );
