import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dartvel_client/dartvel_client.dart';

/// A sign-in form wired the way Dartvel's prebuilt one is, to show a password
/// manager filling it.
///
/// It signs nobody in, so it never tells the manager to save: leaving the
/// form cancels, as the real page does for a password the server refused.
class const PasswordManagerDemo({super.key}) extends StatefulWidget {
  @override
  State<PasswordManagerDemo> createState() => _PasswordManagerDemoState();
}

class _PasswordManagerDemoState extends State<PasswordManagerDemo> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  String? _said;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    // A real sign-in calls TextInput.finishAutofillContext() here, after the
    // server accepts. The demo has no server, so it cancels instead.
    TextInput.finishAutofillContext(shouldSave: false);
    setState(() => _said = _password.text.isEmpty
        ? 'Type or fill a password first.'
        : 'Filled. A real sign-in would now offer to save this password.');
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Material(
          type: .transparency,
          child: AutofillGroup(
            onDisposeAction: AutofillContextAction.cancel,
            child: DVBox.list(<Widget>[
              TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                textInputAction: .next,
                autofillHints: const <String>[
                  AutofillHints.username,
                  AutofillHints.email,
                ],
              ),
              TextField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                textInputAction: .done,
                autofillHints: const <String>[AutofillHints.password],
                onSubmitted: (_) => _submit(),
              ),
              OutlinedButton(
                onPressed: _submit,
                child: const Text('Sign in (demo)'),
              ),
              if (_said != null) DVText(_said!),
            ], spacing: 12),
          ),
        ),
      );
}
