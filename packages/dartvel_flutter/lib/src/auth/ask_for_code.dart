/// Asking somebody for the code an application sent them.
///
/// The other half of `DV.Auth.code()`. Every application that mails a code
/// builds the same thing after it: a field that takes digits and nothing
/// else, a button, and a line that says the code was wrong. This is that,
/// as a modal over whatever is on screen -- `DV.Auth.askForCode(context)` --
/// or as a whole page for a flow that has one, `DV.Auth.AskForCodePage`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Checks a code. Returns null when it is right, or what to tell the person
/// when it is not.
typedef DVCodeCheck = Future<String?> Function(String code);

/// The field, the button and the message, shared by the modal and the page.
class DVCodeEntry extends StatefulWidget {
  const DVCodeEntry({
    super.key,
    this.length = 6,
    this.message,
    this.confirmLabel = 'Continue',
    this.onCancel,
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
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.message != null) ...<Widget>[
          Text(widget.message!, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          // The code is what somebody's password manager and their phone's
          // keyboard both offer to fill in.
          autofillHints: const <String>[AutofillHints.oneTimeCode],
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
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialog) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 320,
        child: DVCodeEntry(
          length: length,
          message: message,
          onCancel: () => Navigator.of(dialog).pop(),
          onSubmit: (String code) async {
            final String? problem = await verify?.call(code);
            if (problem != null) return problem;
            if (dialog.mounted) Navigator.of(dialog).pop(code);
            return null;
          },
        ),
      ),
    ),
  );
}

/// The same question as a page. See `DV.Auth.AskForCodePage`.
class DVAskForCodePage extends StatelessWidget {
  const DVAskForCodePage({
    super.key,
    this.length = 6,
    this.title = 'Enter your code',
    this.message,
    required this.onCode,
  });

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
              padding: const EdgeInsets.all(24),
              child: DVCodeEntry(
                length: length,
                message: message,
                onSubmit: onCode,
              ),
            ),
          ),
        ),
      );
}
