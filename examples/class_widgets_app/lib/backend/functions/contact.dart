import 'dart:convert';
import 'dart:io';

Future<Map<String, String>> handler({
  required String name,
  required String email,
  required String message,
}) async {
  if (name.isEmpty || email.isEmpty || message.isEmpty) {
    throw Exception('All fields are required');
  }

  if (!email.contains('@')) {
    throw Exception('Invalid email address');
  }

  final submissions = File('storage/contact_submissions.jsonl');
  await submissions.parent.create(recursive: true);
  await submissions.writeAsString(
    '${jsonEncode({
          'name': name,
          'email': email,
          'message': message,
          'createdAt': DateTime.now().toIso8601String(),
        })}\n',
    mode: FileMode.append,
  );

  return {
    'success': 'true',
    'message': 'Thank you for contacting us!',
  };
}
