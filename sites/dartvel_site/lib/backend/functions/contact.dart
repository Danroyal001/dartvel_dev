// POST /api/contact (filename without method = POST by default)
import 'dart:io';
import 'dart:convert';

Future<Map<String, Object?>> handler(
    {required String name, required String email, required String message}) async {
  // Validate inputs
  if (name.isEmpty || email.isEmpty || message.isEmpty) {
    throw Exception('All fields are required');
  }

  if (!email.contains('@')) {
    throw Exception('Invalid email address');
  }

  final submission = {
    'name': name,
    'email': email,
    'message': message,
    'receivedAt': DateTime.now().toIso8601String(),
  };
  final inbox = File('storage/contact_submissions.jsonl');
  inbox.parent.createSync(recursive: true);
  inbox.writeAsStringSync('${jsonEncode(submission)}\n',
      mode: FileMode.append, flush: true);

  return {
    'success': true,
    'message': 'Thank you for contacting us!',
  };
}
