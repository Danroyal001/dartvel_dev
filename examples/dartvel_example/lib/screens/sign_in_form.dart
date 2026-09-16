import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../shop/account.dart';
import '../shop/orders.dart';
import '../theme/palette.dart';

/// Email and password against DV.Auth, filled in with the demo account.
class SignInForm extends StatefulWidget {
  const SignInForm({super.key, required this.from});

  /// Where to go once signed in: a path in this app, never another site.
  final String from;

  @override
  State<SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<SignInForm> {
  final TextEditingController _email = TextEditingController(text: demoEmail);
  final TextEditingController _password =
      TextEditingController(text: demoPassword);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Account account =
          await signIn(email: _email.text, password: _password.text);
      await seedOrderHistory(account.email);
      final String from = widget.from;
      final bool local = from.startsWith('/') && !from.startsWith('//');
      DV.Navigation.navigate(DVRouteTarget(local ? from : '/'));
    } on AuthException {
      if (mounted) {
        setState(() => _error = 'That email and password do not match.');
      }
    } on Object {
      if (mounted) setState(() => _error = 'Signing in failed. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    return AutofillGroup(
      child: DVBox.list([
        TextField(
          key: const Key('sign-in-email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const <String>[AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        TextField(
          key: const Key('sign-in-password'),
          controller: _password,
          obscureText: true,
          autofillHints: const <String>[AutofillHints.password],
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null)
          DVText(_error!).modifier(p.muted.color(Theme.of(context).colorScheme.error)),
        FilledButton(
          key: const Key('sign-in-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Signing in…' : 'Sign in'),
        ),
        const DVText('This is a demo account. Everything you do stays on this device.')
            .modifier(p.muted.fontSize(13)),
      ], spacing: 14),
    );
  }
}
