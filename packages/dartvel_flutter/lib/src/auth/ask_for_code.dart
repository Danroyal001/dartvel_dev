/// Asking somebody for the code an application sent them.
///
/// The other half of `DV.Auth.code()`. Every application that mails a code
/// builds the same thing after it: a field that takes digits and nothing
/// else, a button, and a line that says the code was wrong. This is that,
/// as a modal over whatever is on screen -- `DV.Auth.askForCode(context)` --
/// or as a whole page for a flow that has one, `DV.Auth.AskForCodePage`.
library;

import 'package:dartvel_core/dartvel.dart' show DVNotificationChannel;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Checks a code. Returns null when it is right, or what to tell the person
/// when it is not.
typedef DVCodeCheck = Future<String?> Function(String code);

/// The autofill hints for a field taking a code that went out by [sentBy].
///
/// Android has a hint for each: an e-mailed code is `emailOTPCode` (Flutter
/// 3.50), which the mail app can offer, and a texted one `oneTimeCode`, which
/// the messages app offers. iOS and the web read only the first hint and know
/// only `oneTimeCode` (`autocomplete="one-time-code"`), which they fill from
/// mail and messages alike, so there it stays.
List<String> dvOneTimeCodeHints(DVNotificationChannel sentBy) {
  final bool android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  if (android && sentBy == DVNotificationChannel.email) {
    return const <String>[AutofillHints.emailOTPCode];
  }
  return const <String>[AutofillHints.oneTimeCode];
}

/// The field, the button and the message, shared by the modal and the page.
class DVCodeEntry extends StatefulWidget {
  const DVCodeEntry({
    super.key,
    this.length = 6,
    this.message,
    this.confirmLabel = 'Continue',
    this.onCancel,
    this.sentBy = DVNotificationChannel.email,
    required this.onSubmit,
  });

  /// How many digits the code has.
  final int length;

  /// What to say above the field: where the code was sent, usually.
  final String? message;

  final String confirmLabel;

  /// Shown as a second, quieter action when there is somewhere to go back to.
  final VoidCallback? onCancel;

  /// Answers null when the code is accepted, or what to say when it is not.
  final DVCodeCheck onSubmit;

  /// How the code went out, so the field offers it from the right app:
  /// [DVNotificationChannel.email] (the default) or
  /// [DVNotificationChannel.sms]. See [dvOneTimeCodeHints].
  final DVNotificationChannel sentBy;

  @override
  State<DVCodeEntry> createState() => _DVCodeEntryState();
}

class _DVCodeEntryState extends State<DVCodeEntry> {
  final TextEditingController _controller = TextEditingController();
  String? _problem;
  bool _checking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_checking) return;
    final String code = _controller.text;
    if (code.length < widget.length) {
      setState(() => _problem = 'The code is ${widget.length} digits.');
      return;
    }
    setState(() {
      _checking = true;
      _problem = null;
    });
    final String? problem = await widget.onSubmit(code);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        if (widget.message != null) ...<Widget>[
          Text(widget.message!, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: .center,
          // The code is what somebody's password manager and their phone's
          // keyboard both offer to fill in.
          autofillHints: dvOneTimeCodeHints(widget.sentBy),
          maxLength: widget.length,
          style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(widget.length),
          ],
          decoration: InputDecoration(
            counterText: '',
            errorText: _problem,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _checking ? null : _submit,
          child: Text(widget.confirmLabel),
        ),
        if (widget.onCancel != null)
          TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
      ],
    );
  }
}

/// Shows the modal. See `DV.Auth.askForCode`.
Future<String?> dvAskForCode(
  BuildContext context, {
  int length = 6,
  String title = 'Enter your code',
  String? message,
  DVCodeCheck? verify,
  DVNotificationChannel sentBy = DVNotificationChannel.email,
  RouteBarrierBuilder? barrierBuilder,
}) {
  Widget dialogFor(BuildContext dialog) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 320,
        child: DVCodeEntry(
          length: length,
          message: message,
          sentBy: sentBy,
          onCancel: () => Navigator.of(dialog).pop(),
          onSubmit: (String code) async {
            final String? problem = await verify?.call(code);
            if (problem != null) return problem;
            if (dialog.mounted) Navigator.of(dialog).pop(code);
            return null;
          },
        ),
      ),
    );
  if (barrierBuilder == null) {
    return showDialog<String>(context: context, builder: dialogFor);
  }
  // The same route showDialog pushes, with the app's barrier drawn in it.
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push<String>(_DVBarrierDialogRoute<String>(
    context: context,
    builder: dialogFor,
    barrierBuilder: barrierBuilder,
    barrierColor: DialogTheme.of(context).barrierColor ??
        Theme.of(context).dialogTheme.barrierColor ??
        Colors.black54,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
  ));
}

/// A material dialog route whose barrier the application draws.
///
/// What it draws is only drawn: it gets no taps and no semantics. Over it
/// sits a clear ModalBarrier carrying what the default barrier carried --
/// the tap outside that dismisses, the "Dismiss" a screen reader announces,
/// Escape -- so an app that replaces the barrier outright, rather than
/// wrapping the one it is handed, cannot make the dialog impossible to leave
/// or silent to a screen reader.
class _DVBarrierDialogRoute<T> extends DialogRoute<T> {
  _DVBarrierDialogRoute({
    required super.context,
    required super.builder,
    required RouteBarrierBuilder barrierBuilder,
    required super.barrierColor,
    super.themes,
  }) : _drawBarrier = barrierBuilder,
       super(traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop);

  // Not named barrierBuilder: that would override RawDialogRoute's own
  // field, and its buildModalBarrier would run the builder a second time.
  final RouteBarrierBuilder _drawBarrier;

  @override
  Widget buildModalBarrier() {
    final Widget drawn = super.buildModalBarrier();
    return Builder(
      builder: (BuildContext context) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ExcludeSemantics(
            child: IgnorePointer(
              child: _drawBarrier(
                context,
                RouteBarrierDetails(
                  animation: animation!,
                  barrierColor: barrierColor,
                  barrierLabel: barrierLabel,
                  barrierDismissible: barrierDismissible,
                ),
                drawn,
              ),
            ),
          ),
          ModalBarrier(
            dismissible: barrierDismissible,
            semanticsLabel: barrierLabel,
            barrierSemanticsDismissible: semanticsDismissible,
          ),
        ],
      ),
    );
  }
}

/// The same question as a page. See `DV.Auth.AskForCodePage`.
class DVAskForCodePage extends StatelessWidget {
  const DVAskForCodePage({
    super.key,
    this.length = 6,
    this.title = 'Enter your code',
    this.message,
    this.sentBy = DVNotificationChannel.email,
    required this.onCode,
  });

  /// How the code went out; see [DVCodeEntry.sentBy].
  final DVNotificationChannel sentBy;

  final int length;
  final String title;
  final String? message;

  /// What to do with the code. Answer with what to tell the person when it
  /// is wrong, or null when it was right.
  final Future<String?> Function(String code) onCode;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const .all(24),
              child: DVCodeEntry(
                length: length,
                message: message,
                sentBy: sentBy,
                onSubmit: onCode,
              ),
            ),
          ),
        ),
      );
}
