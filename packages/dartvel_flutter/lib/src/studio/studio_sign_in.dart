/// Studio's sign-in: a page of the Studio app, at `<mount>/login`.
///
/// Studio signs people in itself rather than sending them to the
/// application's `/login`, which an application can turn off, move or
/// replace, and whose router does not know the mount exists. It signs in
/// against the application's own accounts, through the auth endpoints the
/// mount answers at `<mount>/api/auth/*`, asks for the second factor when
/// the account has one, and then asks the mount whether this person may open
/// Studio at all. Studio itself is loaded from the server, which decides on
/// the Studio.access grant; nothing here grants anything.
library;

import 'package:flutter/material.dart';

import '../../dartvel_flutter.dart';

/// Where, inside [mount], a person signing in is sent afterwards.
///
/// Only a path inside the mount, and never the sign-in itself. Anything else
/// -- another site, a protocol-relative `//host`, a page of the application
/// -- is Studio's front page: a sign-in that could be pointed anywhere is a
/// link somebody can send a person to.
String dvStudioSignInTarget(String mount, String? from) {
  final String home = '$mount/';
  final String value = from ?? '';
  if (value.contains('//') || value.contains('\\')) return home;
  final bool inside = value == mount || value.startsWith('$mount/');
  final bool login =
      value == '$mount/login' || value.startsWith('$mount/login?');
  return inside && !login ? value : home;
}

/// The sign-in page.
class DVStudioSignInScreen extends StatefulWidget {
  const DVStudioSignInScreen({
    super.key,
    required this.client,
    required this.mount,
    this.from,
    this.title = 'Studio',
    required this.open,
  });

  final DVStudioClient client;

  /// The admin mount, with no trailing slash: `/__studio`.
  final String mount;

  /// Where the person was going when they were sent here.
  final String? from;

  final String title;

  /// Loads [path] from the server, as a page.
  final void Function(String path) open;

  @override
  State<DVStudioSignInScreen> createState() => _DVStudioSignInScreenState();
}

class _DVStudioSignInScreenState extends State<DVStudioSignInScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _code = TextEditingController();
  bool _askingForCode = false;
  bool _busy = false;
  String? _problem;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<DVStudioReply> _post(String path, Map<String, Object?> body) =>
      widget.client.transport('POST', path, body: body);

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      if (!_askingForCode) {
        final DVStudioReply reply = await _post('api/auth/sign-in',
            <String, Object?>{'email': _email.text.trim(), 'password': _password.text});
        if (reply.status == 429) {
          return _say('Too many attempts. Wait a minute and try again.');
        }
        if (reply.status != 200) {
          return _say('That email and password do not match an account.');
        }
        final Object? body = reply.body;
        if (body is Map && body['mfaRequired'] == true) {
          setState(() => _askingForCode = true);
          return;
        }
      } else {
        final String value = _code.text.trim();
        final bool digits = RegExp(r'^[0-9 ]+$').hasMatch(value);
        final DVStudioReply reply = await _post(
            'api/auth/second-factor',
            digits
                ? <String, Object?>{'code': value.replaceAll(' ', '')}
                : <String, Object?>{'recoveryCode': value});
        if (reply.status != 200) {
          return _say('That code did not match. Try the next one.');
        }
      }
      final DVStudioReply access =
          await widget.client.transport('GET', 'api/access');
      final Object? body = access.body;
      if (access.status != 200 || body is! Map || body['granted'] != true) {
        return _say('This account may not open Studio.');
      }
      widget.open(dvStudioSignInTarget(widget.mount, widget.from));
    } on Object {
      _say('Could not reach the server. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String problem) {
    if (mounted) setState(() => _problem = problem);
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    required String key,
    bool secret = false,
    bool autofocus = false,
    Iterable<String>? autofill,
  }) {
    return DVBox.list(
      <Widget>[
        DVStudioStyle.caption(label, color: DVStudioStyle.ink),
        TextField(
          key: ValueKey<String>(key),
          controller: controller,
          obscureText: secret,
          autofocus: autofocus,
          autofillHints: autofill,
          enabled: !_busy,
          onSubmitted: (_) => _submit(),
          style: const TextStyle(fontSize: 14, color: DVStudioStyle.ink),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: DVStudioStyle.canvas,
            contentPadding: const .symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: .circular(DVStudioStyle.radius),
              borderSide: const BorderSide(color: DVStudioStyle.lineStrong),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: .circular(DVStudioStyle.radius),
              borderSide: const BorderSide(color: DVStudioStyle.lineStrong),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: .circular(DVStudioStyle.radius),
              borderSide:
                  const BorderSide(color: DVStudioStyle.accent, width: 1.5),
            ),
          ),
        ),
      ],
      spacing: 6,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget form = DVBox.list(
      <Widget>[
        const SizedBox(
          width: 36,
          height: 36,
          child: CustomPaint(painter: DVStudioMarkPainter()),
        ),
        DVBox.list(
          <Widget>[
            DVStudioStyle.title('Sign in to Studio'),
            DVStudioStyle.caption(_askingForCode
                ? 'Enter the code from your authenticator app, or a recovery '
                    'code.'
                : widget.title),
          ],
          spacing: 4,
        ),
        if (!_askingForCode) ...<Widget>[
          _field('Email', _email,
              key: 'dv-studio-sign-in-email',
              autofocus: true,
              autofill: const <String>[AutofillHints.username, AutofillHints.email]),
          _field('Password', _password,
              key: 'dv-studio-sign-in-password',
              secret: true,
              autofill: const <String>[AutofillHints.password]),
        ] else
          _field('Code', _code,
              key: 'dv-studio-sign-in-code',
              autofocus: true,
              autofill: const <String>[AutofillHints.oneTimeCode]),
        if (_problem != null)
          DVStudioStyle.banner(
            tone: DVStudioStyle.danger,
            icon: Icons.error_outline,
            child: Text(_problem!,
                style: DVStudioStyle.bannerText(DVStudioStyle.danger)),
          ),
        Semantics(
          button: true,
          label: _askingForCode ? 'Continue' : 'Sign in',
          child: GestureDetector(
            key: const ValueKey<String>('dv-studio-sign-in-submit'),
            behavior: .opaque,
            onTap: _busy ? null : _submit,
            child: MouseRegion(
              cursor: _busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
              child: Container(
                height: 40,
                alignment: .center,
                decoration: BoxDecoration(
                  color: _busy ? DVStudioStyle.accentSoft : DVStudioStyle.accent,
                  borderRadius: .circular(DVStudioStyle.radius),
                ),
                child: DVText(_busy
                        ? 'Signing in…'
                        : _askingForCode
                            ? 'Continue'
                            : 'Sign in')
                    .modifier(const DVModifier()
                        .fontSize(14)
                        .color(const Color(0xFFFFFFFF))
                        .fontWeight(.w600)),
              ),
            ),
          ),
        ),
      ],
      spacing: DVStudioStyle.space5,
    );

    return Material(
      color: DVStudioStyle.canvas,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const .all(DVStudioStyle.space4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const .all(DVStudioStyle.space8 - 4),
                decoration: BoxDecoration(
                  color: DVStudioStyle.surface,
                  border: Border.all(color: DVStudioStyle.line),
                  borderRadius: .circular(DVStudioStyle.radiusLarge),
                ),
                child: AutofillGroup(child: form),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
