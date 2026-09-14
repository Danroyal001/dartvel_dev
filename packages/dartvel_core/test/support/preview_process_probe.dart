// Run as a process of its own by preview_startup_test.dart.
//
// What it checks is what a process does with the environment it was started
// in before any Dartvel startup code has run -- which a test cannot ask of its
// own process, whose environment was fixed when the runner started it.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';

class RecordingMail implements DVMailProvider {
  final List<DVMailMessage> sent = <DVMailMessage>[];
  @override
  Future<void> send(DVMailMessage message) async => sent.add(message);
}

Future<void> main() async {
  final RecordingMail mail = RecordingMail();
  const DVNotificationMail().useProvider(mail);
  await const DVNotificationMail().send(
    const DVMailMessage(
      from: DVMailAddress('shop@example.com'),
      to: <DVMailAddress>[DVMailAddress('ada@example.com')],
      subject: 'Welcome',
      text: 'Hello',
    ),
  );

  String? queue;
  String? queueError;
  try {
    const DVQueues().useAdapter(DVInMemoryQueueAdapter());
    queue = (await const DVQueues().dispatch<String>('job')).queue;
  } catch (error) {
    queueError = '$error';
  }

  stdout.writeln(
    jsonEncode(<String, Object?>{
      'providerSent': mail.sent.length,
      'captured': DVPreviewOutbound.mail.length,
      'queue': queue,
      'queueError': queueError,
    }),
  );
}
