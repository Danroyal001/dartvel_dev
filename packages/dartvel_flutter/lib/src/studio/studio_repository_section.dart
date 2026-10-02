/// Studio's GitHub section: the project's repository, what Studio would
/// change in it, and the way to send those changes -- a pull request to
/// review, or a push to the base branch -- so the next release carries what
/// was made in Studio.
library;

import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

class DVStudioRepositorySection extends StatefulWidget {
  const DVStudioRepositorySection({super.key, required this.client});

  final DVStudioClient client;

  @override
  State<DVStudioRepositorySection> createState() =>
      _DVStudioRepositorySectionState();
}

class _DVStudioRepositorySectionState extends State<DVStudioRepositorySection> {
  Map<String, Object?>? _state;
  String _name = '';
  String _base = 'main';
  String _message = '';
  String? _problem;
  String? _sent;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final DVStudioReply reply = await widget.client.transport('GET', 'api/repository');
      if (!mounted) return;
      final Object? body = reply.body;
      setState(() {
        _state = body is Map ? body.cast<String, Object?>() : <String, Object?>{};
        if (_state!['repository'] is String) _name = _state!['repository']! as String;
        if (_state!['base'] is String) _base = _state!['base']! as String;
        _problem = reply.status == 200
            ? _state!['problem'] as String?
            : '${_state!['message'] ?? 'The server answered ${reply.status}.'}';
      });
    } on Object catch (error) {
      if (mounted) setState(() => _problem = '$error');
    }
  }

  Future<void> _run(String method, String path, Map<String, Object?> body,
      {bool result = false}) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final DVStudioReply reply =
          await widget.client.transport(method, path, body: body);
      final Object? answer = reply.body;
      final Map<Object?, Object?> json = answer is Map ? answer : const <Object?, Object?>{};
      if (reply.status != 200) {
        if (mounted) {
          setState(() => _problem =
              '${json['message'] ?? 'The server answered ${reply.status}.'}');
        }
        return;
      }
      if (result && mounted) setState(() => _sent = '${json['url'] ?? ''}');
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, Object?>? state = _state;
    if (state == null) return DVStudioStyle.placeholder('Loading…');
    final List<Map<String, Object?>> changes = <Map<String, Object?>>[
      for (final Object? c in (state['changes'] as List?) ?? const <Object?>[])
        if (c is Map) c.cast<String, Object?>(),
    ];
    final bool connected = state['connected'] == true;
    final bool token = state['token'] == true;
    return ColoredBox(
      color: DVStudioStyle.canvas,
      child: ListView(
        padding: const .all(DVStudioStyle.space6),
        children: <Widget>[
          DVStudioStyle.title('GitHub'),
          const SizedBox(height: DVStudioStyle.space1),
          DVStudioStyle.body(
            'Send what you made in Studio to the project\'s repository, so '
            'the next release of the app is built with it.',
            color: DVStudioStyle.muted,
          ),
          const SizedBox(height: DVStudioStyle.space4),
          DVStudioStyle.card(
            padding: const .all(DVStudioStyle.space4),
            child: Column(
              crossAxisAlignment: .stretch,
              children: <Widget>[
                DVStudioStyle.overline('Repository'),
                const SizedBox(height: DVStudioStyle.space2),
                Row(
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: KeyedSubtree(
                        key: const ValueKey<String>('dv-studio-repository-name'),
                        child: DVStudioTextInput(
                          value: _name,
                          placeholder: 'owner/name, like roastery/site',
                          icon: Icons.book_outlined,
                          onChanged: (String v) => _name = v,
                        ),
                      ),
                    ),
                    const SizedBox(width: DVStudioStyle.space2),
                    Expanded(
                      child: KeyedSubtree(
                        key: const ValueKey<String>('dv-studio-repository-base'),
                        child: DVStudioTextInput(
                          value: _base,
                          label: 'Branch',
                          onChanged: (String v) => _base = v,
                        ),
                      ),
                    ),
                    const SizedBox(width: DVStudioStyle.space2),
                    _button('dv-studio-repository-connect',
                        connected ? 'Save' : 'Connect',
                        _busy
                            ? null
                            : () => unawaited(_run('PUT', 'api/repository',
                                <String, Object?>{'repository': _name.trim(), 'base': _base.trim()}))),
                  ],
                ),
                const SizedBox(height: DVStudioStyle.space2),
                DVStudioStyle.caption(
                  token
                      ? 'Sending with the server\'s GitHub token.'
                      : '${state['tokenHelp'] ?? 'The server has no GitHub token.'}',
                  color: token ? DVStudioStyle.muted : DVStudioStyle.warning,
                ),
              ],
            ),
          ),
          if (_problem != null) ...<Widget>[
            const SizedBox(height: DVStudioStyle.space3),
            DVStudioStyle.body(_problem!, color: DVStudioStyle.danger),
          ],
          if (_sent != null) ...<Widget>[
            const SizedBox(height: DVStudioStyle.space3),
            DVStudioStyle.body('Sent: $_sent', color: DVStudioStyle.success),
          ],
          if (connected && token) ...<Widget>[
            const SizedBox(height: DVStudioStyle.space5),
            DVStudioStyle.heading(changes.isEmpty
                ? 'The repository has everything made in Studio'
                : changes.length == 1
                    ? '1 file would change'
                    : '${changes.length} files would change'),
            const SizedBox(height: DVStudioStyle.space3),
            for (final Map<String, Object?> change in changes) _change(change),
            if (changes.isNotEmpty) ...<Widget>[
              const SizedBox(height: DVStudioStyle.space3),
              KeyedSubtree(
                key: const ValueKey<String>('dv-studio-repository-message'),
                child: DVStudioTextInput(
                  value: _message,
                  placeholder: 'What changed, in a line',
                  onChanged: (String v) => _message = v,
                ),
              ),
              const SizedBox(height: DVStudioStyle.space2),
              Row(
                children: <Widget>[
                  _button(
                    'dv-studio-repository-pull-request',
                    'Open a pull request',
                    _busy
                        ? null
                        : () => unawaited(_run('POST', 'api/repository/sync',
                            <String, Object?>{'mode': 'pullRequest', 'message': _message},
                            result: true)),
                    primary: true,
                  ),
                  const SizedBox(width: DVStudioStyle.space2),
                  _button(
                    'dv-studio-repository-push',
                    'Push to ${state['base'] ?? 'main'}',
                    _busy
                        ? null
                        : () => unawaited(_run('POST', 'api/repository/sync',
                            <String, Object?>{'mode': 'push', 'message': _message},
                            result: true)),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _change(Map<String, Object?> change) {
    final String kind = '${change['kind']}';
    return Padding(
      padding: const .only(bottom: DVStudioStyle.space3),
      child: DVStudioStyle.card(
        padding: const .all(DVStudioStyle.space3),
        child: Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                DVStudioStyle.badge(
                  switch (kind) {
                    'added' => 'New',
                    'removed' => 'Removed',
                    _ => 'Changed',
                  },
                  tone: switch (kind) {
                    'added' => DVStudioStyle.success,
                    'removed' => DVStudioStyle.danger,
                    _ => DVStudioStyle.warning,
                  },
                ),
                const SizedBox(width: DVStudioStyle.space2),
                Expanded(child: Text('${change['path']}')),
              ],
            ),
            const SizedBox(height: DVStudioStyle.space2),
            for (final String line in '${change['diff'] ?? ''}'.split('\n'))
              Text(
                line,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: line.startsWith('+')
                      ? DVStudioStyle.success
                      : line.startsWith('-')
                          ? DVStudioStyle.danger
                          : DVStudioStyle.muted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Widget _button(String key, String label, VoidCallback? onTap, {bool primary = false}) =>
    DVStudioControl(
      key: ValueKey<String>(key),
      label: label,
      enabled: onTap != null,
      onTap: onTap,
      primary: primary,
    );
