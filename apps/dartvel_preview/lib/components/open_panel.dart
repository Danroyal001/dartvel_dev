import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dartvel_client/dartvel_client.dart';
import 'preview_decision.dart';
import 'preview_launch.dart';
import 'preview_platform.dart';

/// Where the reader pastes or receives a link, and what happened to it.
class const PreviewOpenPanel({
  super.key,
  final bool? runsCode,
  final bool? showsWeb,
  final Future<String> Function(Uri pairing)? pair,
}) extends StatefulWidget {
  @override
  State<PreviewOpenPanel> createState() => _PreviewOpenPanelState();
}

class _PreviewOpenPanelState extends State<PreviewOpenPanel> {
  final TextEditingController _link = TextEditingController();
  String? _error;
  String? _status;
  Uri? _browserUrl;

  bool get _runsCode => widget.runsCode ?? previewRunsCode;
  bool get _showsWeb => widget.showsWeb ?? previewShowsWeb;

  @override
  void initState() {
    super.initState();
    final String? launched = previewLaunchLink;
    if (launched != null) {
      previewLaunchLink = null;
      _link.text = launched;
      scheduleMicrotask(() => _open(launched));
    }
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _open(String text) async {
    final DVPreviewAppLink link;
    try {
      link = DVPreviewAppLink.parse(text);
    } on FormatException catch (error) {
      setState(() {
        _error = error.message;
        _status = null;
        _browserUrl = null;
      });
      return;
    }
    final PreviewDecision decision =
        previewDecide(link, runsCode: _runsCode, showsWeb: _showsWeb);
    setState(() {
      _error = null;
      _browserUrl = null;
      _status = decision.message.isEmpty ? null : decision.message;
    });
    switch (decision.action) {
      case PreviewAction.pair:
        setState(() => _status = 'Pairing with ${link.label}...');
        final String next =
            await (widget.pair ?? previewPair)(decision.url!);
        if (mounted) setState(() => _status = next);
      case PreviewAction.showWeb:
        if (!mounted) return;
        context.go(DVRoutes.frame
            .withQuery(<String, String>{'url': decision.url.toString()})
            .path);
      case PreviewAction.openInBrowser:
        setState(() => _browserUrl = decision.url);
      case PreviewAction.cannot:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return DVBox.list(<Widget>[
      TextField(
        controller: _link,
        onSubmitted: _open,
        textInputAction: TextInputAction.go,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: 'Link from dartvel dev',
          hintText: 'dartvel-preview://open?...',
          errorText: _error,
          errorMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
      ),
      FilledButton(
        onPressed: () => _open(_link.text),
        child: const Text('Open'),
      ),
      if (_status != null)
        DVText(_status!).modifier(const DVModifier().color(colors.onSurfaceVariant)),
      if (_browserUrl != null)
        DVBox.row(<Widget>[
          Expanded(child: SelectableText(_browserUrl.toString())),
          IconButton(
            tooltip: 'Copy the address',
            icon: const Icon(Icons.copy),
            onPressed: () => Clipboard.setData(
                ClipboardData(text: _browserUrl.toString())),
          ),
        ], spacing: 8),
    ], spacing: 12, crossAlign: .stretch);
  }
}
