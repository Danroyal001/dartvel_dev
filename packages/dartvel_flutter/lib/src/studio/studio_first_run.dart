/// The first-run setup, a page of the Studio app at `<mount>/setup`.
///
/// An application that has never run mints an owner, prints an address and a
/// long password, and writes the same pair to a file only the owner can read.
/// Until that owner has replaced the password and turned on a second factor,
/// the mount answers nothing at all but this page, so the page has to render
/// before anybody has signed in and before the project itself may be touched.
///
/// It is the Studio app drawing that page rather than the server writing one,
/// which is the same reason Studio's sign-in is a page of the app at
/// `<mount>/login`: one Studio, drawn the same way on every target, instead of
/// a second hand-written screen that only a browser can show. The four things
/// the page does are the application's own auth endpoints, answered at the
/// mount, so the rate limit, the CSRF check and the session rotation are the
/// ones already written rather than a second copy of each.
///
/// It asks for the address rather than printing it, and it holds nothing: a
/// page served before anybody has signed in is open to the internet by
/// definition, and naming the owner on it hands half a credential to whoever
/// found the mount.
library;

import 'package:flutter/material.dart';

import '../../dartvel_flutter.dart';

/// The setup page.
class DVStudioFirstRunScreen extends StatefulWidget {
  const DVStudioFirstRunScreen({
    super.key,
    required this.client,
    required this.mount,
    this.title = 'Studio',
    required this.open,
  });

  final DVStudioClient client;

  /// The admin mount, with no trailing slash: `/__studio`.
  final String mount;

  final String title;

  /// Loads a path from the server, as a page.
  final void Function(String path) open;

  @override
  State<DVStudioFirstRunScreen> createState() => _DVStudioFirstRunScreenState();
}

class _DVStudioFirstRunScreenState extends State<DVStudioFirstRunScreen> {
  final TextEditingController _address = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _chosen = TextEditingController();
  final TextEditingController _code = TextEditingController();

  /// The authenticator has been started and is waiting for its first code.
  bool _enrolling = false;

  /// The password has been changed, and the authenticator has not. The one
  /// half of the setup that cannot be undone, so from here the password this
  /// page asks for is the one the owner just chose, not the printed one.
  bool _changed = false;

  /// The secret the authenticator app is given, from the server.
  String _secret = '';

  bool _busy = false;
  String? _problem;

  @override
  void dispose() {
    _address.dispose();
    _password.dispose();
    _chosen.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<DVStudioReply> _post(String path, Map<String, Object?> body) =>
      widget.client.transport('POST', path, body: body);

  /// What the server said, when it said something a person can act on.
  static String? _said(DVStudioReply reply, String fallback) {
    final Object? body = reply.body;
    if (body is Map) {
      final Object? message = body['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    return fallback;
  }

  Future<void> _change() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final DVStudioReply signedIn = await _post('api/auth/sign-in',
          <String, Object?>{
            'email': _address.text.trim(),
            'password': _password.text,
          });
      if (signedIn.status == 429) {
        return _say('Too many attempts. Wait a minute and try again.');
      }
      if (signedIn.status != 200) {
        return _say('That is not the address and password this application '
            'printed.');
      }
      // A pending setup has no second factor to present: one can only be
      // turned on from here. An account that has one is somebody who is back
      // on a page they have already finished, and the sign-in is the way in.
      final Object? signedInWith = signedIn.body;
      if (signedInWith is Map && signedInWith['mfaRequired'] == true) {
        _say('This setup has already been finished. Sign in instead.');
        widget.open('${widget.mount}/login');
        return;
      }
      if (!_changed) {
        final DVStudioReply changed = await _post(
            'api/auth/account/password', <String, Object?>{
          'currentPassword': _password.text,
          'newPassword': _chosen.text,
        });
        if (changed.status != 200) {
          return _say(_said(changed, 'That password could not be changed.')!);
        }
      }
      final DVStudioReply started = await _post(
          'api/auth/factors/totp', const <String, Object?>{});
      if (started.status != 200) {
        // The password is changed and the factor is not, so the setup is still
        // pending and the printed password no longer opens it. Stay on this
        // step, which now asks for the password that does.
        setState(() => _changed = true);
        return _say(_said(
            started, 'The authenticator could not be started right now.')!);
      }
      final Object? body = started.body;
      final Object? secret = body is Map ? body['secret'] : null;
      setState(() {
        _secret = secret is String ? secret : '';
        _enrolling = true;
      });
    } on Object {
      _say('Could not reach the server. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final DVStudioReply done = await _post(
          'api/auth/factors/totp/confirm', <String, Object?>{'code': _code.text.trim()});
      if (done.status != 200) {
        return _say('That code did not match. Try the next one.');
      }
      // The setup is done, and the server is now the thing that decides what
      // this mount answers: going to its front page is the whole of what is
      // left to do.
      widget.open('${widget.mount}/');
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
          key: ValueKey<String>('dv-studio-setup-$key'),
          controller: controller,
          obscureText: secret,
          autofocus: autofocus,
          autofillHints: autofill,
          enabled: !_busy,
          onSubmitted: (_) => _change(),
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

  /// The button that ends this step, in the same shape the sign-in's is.
  Widget _action(String key, String label, String busyLabel, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        key: ValueKey<String>('dv-studio-setup-$key'),
        behavior: .opaque,
        onTap: _busy ? null : onTap,
        child: MouseRegion(
          cursor: _busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
          child: Container(
            height: 40,
            alignment: .center,
            decoration: BoxDecoration(
              color: _busy ? DVStudioStyle.accentSoft : DVStudioStyle.accent,
              borderRadius: .circular(DVStudioStyle.radius),
            ),
            child: DVText(_busy ? busyLabel : label)
                .modifier(const DVModifier()
                    .fontSize(14)
                    .color(const Color(0xFFFFFFFF))
                    .fontWeight(.w600)),
          ),
        ),
      ),
    );
  }

  Widget _problemBanner() {
    final String? problem = _problem;
    if (problem == null) return const SizedBox.shrink();
    return DVStudioStyle.banner(
      tone: DVStudioStyle.danger,
      icon: Icons.error_outline,
      child: Text(problem, style: DVStudioStyle.bannerText(DVStudioStyle.danger)),
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
            DVStudioStyle.title('Finish setting up'),
            DVStudioStyle.caption(_enrolling
                ? 'Scan this in an authenticator app, or type the key into it.'
                : 'This application printed a password when it first ran. '
                    'Studio opens once you have replaced it and turned on a '
                    'second factor.'),
          ],
          spacing: 4,
        ),
        if (_enrolling) ...<Widget>[
          Container(
            width: double.infinity,
            padding: const .all(DVStudioStyle.space3),
            decoration: BoxDecoration(
              color: DVStudioStyle.canvas,
              border: Border.all(color: DVStudioStyle.line),
              borderRadius: .circular(DVStudioStyle.radius),
            ),
            child: DVText(_secret)
                .modifier(const DVModifier()
                    .fontSize(13)
                    .color(DVStudioStyle.ink)
                    .fontFamily('monospace')),
          ),
          _field('The six digits it shows', _code,
              key: 'code',
              autofocus: true,
              autofill: const <String>[AutofillHints.oneTimeCode]),
          _problemBanner(),
          _action('confirm', 'Turn it on', 'Turning it on…', _confirm),
        ] else ...<Widget>[
          _field('The address it printed', _address,
              key: 'address',
              autofocus: true,
              autofill:
                  const <String>[AutofillHints.username, AutofillHints.email]),
          _field(_changed ? 'Your new password' : 'The password it printed',
              _password,
              key: 'password',
              secret: true,
              autofill: const <String>[AutofillHints.password]),
          if (!_changed) ...<Widget>[
            _field('A new password of your own', _chosen,
                key: 'new-password',
                secret: true,
                autofill: const <String>[AutofillHints.newPassword]),
            DVStudioStyle.caption('Both are in the line this application '
                'printed when it first ran, and in '
                'initial-owner-password.txt beside its database.'),
          ],
          _problemBanner(),
          _action('submit',
              _changed ? 'Try the authenticator again' : 'Change it',
              'Working…',
              _change),
        ],
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
