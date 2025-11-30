// POST /api/contact (filename without method = POST by default)
import 'dart:convert';

Future<Map<String, dynamic>> handler(
    {required String name, required String email, required String message}) async {
  // Validate inputs
  if (name.isEmpty || email.isEmpty || message.isEmpty) {
    throw Exception('All fields are required');
  }

  if (!email.contains('@')) {
    throw Exception('Invalid email address');
  }

  // TODO: Send email, save to database, etc.
  print('Contact form submission:');
  print('  Name: $name');
  print('  Email: $email');
  print('  Message: $message');

  return {
    'success': true,
    'message': 'Thank you for contacting us!',
  };
}
