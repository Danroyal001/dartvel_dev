/// Studio's Platforms screen: settings that belong to one platform, written
/// to the same `dartvel.platforms` object a project writes in code.
///
/// Web is the first: the project's own HTML at the three edges of every page
/// (inside the head, right after the body opens, right before it closes),
/// each piece typed here or taken from a file under `html/`. It is checked as
/// it is typed, by the same rules the build refuses a page-breaking snippet
/// with, and saved through Studio's API: into `pubspec.yaml` on a development
/// server, and through the GitHub screen on a deployed one. The build writes
/// it into the shell every page is made from.
///
/// `<mount>/platforms` lists the platforms and `<mount>/platforms/web` is the
/// Web screen, each at its own address. Only platforms whose settings Studio
/// can really change are listed; there are no placeholders.
library;

import 'dart:async';

import 'package:dartvel_core/config.dart'
    show DVDocumentSlot, dvHtmlSnippetProblems, dvWebFileProblem;
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show Icons;

import '../../dartvel_flutter.dart';

/// How a person reads each slot.
String _slotLabel(DVDocumentSlot slot) => switch (slot) {
      DVDocumentSlot.head => 'Inside the head',
      DVDocumentSlot.bodyStart => 'Start of the page body',
      DVDocumentSlot.bodyEnd => 'End of the page body',
    };

String _slotHelp(DVDocumentSlot slot) => switch (slot) {
      DVDocumentSlot.head =>
        'Tags a browser reads before the page: meta tags, verification tags, '
            'stylesheets, and scripts that must load first.',
      DVDocumentSlot.bodyStart =>
        'Right after the page body opens: the part of a tag manager that '
            'works without scripts.',
      DVDocumentSlot.bodyEnd =>
        'Right before the page body closes, after the page itself: chat '
            'widgets and scripts that can wait.',
    };

/// One piece of HTML being edited: typed in, or the path of a file.
class _Snippet {
  _Snippet.html(this.text) : file = false;
  _Snippet.file(this.text) : file = true;

  final bool file;
  String text;

  Map<String, Object?> toJson() =>
      file ? <String, Object?>{'file': text.trim()} : <String, Object?>{'html': text};
}

/// The Platforms screen. [platform] is the platform open in it (`web`), or
/// null for the list; [onSelect] opens one, which moves the address.
class DVStudioPlatformsSection extends StatefulWidget {
  const DVStudioPlatformsSection({
    super.key,
    required this.client,
    this.platform,
    required this.onSelect,
  });

  final DVStudioClient client;
  final String? platform;
  final void Function(String platform) onSelect;

  @override
  State<DVStudioPlatformsSection> createState() => _DVStudioPlatformsSectionState();
}

class _DVStudioPlatformsSectionState extends State<DVStudioPlatformsSection> {
  Map<String, Object?>? _state;
  final Map<DVDocumentSlot, List<_Snippet>> _slots = <DVDocumentSlot, List<_Snippet>>{
    for (final DVDocumentSlot slot in DVDocumentSlot.values) slot: <_Snippet>[],
  };
  String? _problem;
  String? _saved;
  List<String> _serverProblems = const <String>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final DVStudioReply reply = await widget.client.transport('GET', 'api/platforms');
      if (!mounted) return;
      final Object? body = reply.body;
      final Map<String, Object?> state = body is Map ? body.cast<String, Object?>() : <String, Object?>{};
      setState(() {
        _state = state;
        _problem = reply.status == 200 ? null : '${state['message'] ?? 'The server answered ${reply.status}.'}';
        final Object? web = state['web'];
        final Object? document = web is Map ? web['document'] : null;
        for (final DVDocumentSlot slot in DVDocumentSlot.values) {
          final Object? entries = document is Map ? document[slot.key] : null;
          _slots[slot] = <_Snippet>[
            for (final Object? entry in entries is List ? entries : const <Object?>[])
              if (entry is Map && entry['file'] != null)
                _Snippet.file('${entry['file']}')
              else if (entry is Map)
                _Snippet.html('${entry['html'] ?? ''}'),
          ];
        }
      });
    } on Object catch (error) {
      if (mounted) setState(() => _problem = '$error');
    }
  }

  /// Why [snippet] would break the page, checked as it is typed.
  List<String> _problemsOf(DVDocumentSlot slot, _Snippet snippet) {
    final String text = snippet.text.trim();
    if (text.isEmpty) return <String>[snippet.file ? 'Name a file under html/, such as html/head.html.' : 'Type or paste the HTML.'];
    if (snippet.file) {
      final String? wrong = dvWebFileProblem(text);
      if (wrong != null) return <String>[wrong];
      final Map<Object?, Object?> files = _state?['files'] is Map ? _state!['files']! as Map : const <Object?, Object?>{};
      final List<Object?> known = _state?['webFiles'] is List ? _state!['webFiles']! as List<Object?> : const <Object?>[];
      final Object? contents = files[text];
      if (contents is String) return dvHtmlSnippetProblems(contents, slot: slot);
      if (!known.contains(text) && _state?['development'] != true) {
        return <String>['$text is not one of this build\'s files under html/.'];
      }
      return const <String>[];
    }
    return dvHtmlSnippetProblems(snippet.text, slot: slot);
  }

  bool get _valid => DVDocumentSlot.values.every(
        (DVDocumentSlot slot) => _slots[slot]!.every((_Snippet s) => _problemsOf(slot, s).isEmpty),
      );

  Map<String, Object?> get _document => <String, Object?>{
        for (final DVDocumentSlot slot in DVDocumentSlot.values)
          if (_slots[slot]!.isNotEmpty)
            slot.key: <Object?>[for (final _Snippet snippet in _slots[slot]!) snippet.toJson()],
      };

  Future<void> _save() async {
    if (_busy || !_valid) {
      setState(() => _saved = null);
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
      _serverProblems = const <String>[];
    });
    try {
      final DVStudioReply reply = await widget.client
          .transport('PUT', 'api/platforms/web/document', body: <String, Object?>{'document': _document});
      final Object? answer = reply.body;
      final Map<Object?, Object?> json = answer is Map ? answer : const <Object?, Object?>{};
      if (!mounted) return;
      if (reply.status != 200) {
        setState(() {
          _problem = '${json['message'] ?? 'The server answered ${reply.status}.'}';
          _serverProblems = <String>[
            for (final Object? line in (json['problems'] as List?) ?? const <Object?>[]) '$line',
          ];
        });
        return;
      }
      setState(() => _saved = json['written'] != null
          ? 'Saved to ${json['written']}. Every page carries it from the next build.'
          : 'Saved. Send it to the repository from the GitHub screen; every page '
              'carries it from the next build after that.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, Object?>? state = _state;
    if (state == null) return DVStudioStyle.placeholder(_problem ?? 'Loading…');
    return ColoredBox(
      color: DVStudioStyle.canvas,
      child: ListView(
        padding: const .all(DVStudioStyle.space6),
        children: widget.platform == 'web' ? _web(state) : _list(state),
      ),
    );
  }

  List<Widget> _list(Map<String, Object?> state) {
    final int count = DVDocumentSlot.values.fold(0, (int sum, DVDocumentSlot slot) => sum + _slots[slot]!.length);
    return <Widget>[
      DVStudioStyle.title('Platforms'),
      const SizedBox(height: DVStudioStyle.space1),
      DVStudioStyle.body(
        'Settings that belong to one platform. They are saved to the project\'s '
        'configuration, the same settings its code uses.',
        color: DVStudioStyle.muted,
      ),
      const SizedBox(height: DVStudioStyle.space4),
      DVStudioStyle.card(
        padding: const .all(DVStudioStyle.space4),
        child: Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            DVStudioStyle.heading('Web'),
            const SizedBox(height: DVStudioStyle.space1),
            DVStudioStyle.body(
              'HTML every page carries: in its head, and at the start and end of its body.',
              color: DVStudioStyle.muted,
            ),
            const SizedBox(height: DVStudioStyle.space2),
            DVStudioStyle.caption(switch (count) {
              0 => 'No HTML added yet.',
              1 => '1 piece of HTML on every page.',
              _ => '$count pieces of HTML on every page.',
            }),
            const SizedBox(height: DVStudioStyle.space3),
            Align(
              alignment: Alignment.centerLeft,
              child: _button('dv-studio-platforms-open-web', 'Open Web settings', () => widget.onSelect('web'),
                  primary: true, icon: Icons.language),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _web(Map<String, Object?> state) {
    final bool canEdit = state['canEdit'] == true;
    final String source = '${state['source'] ?? 'pubspec'}';
    return <Widget>[
      DVStudioStyle.title('Web'),
      const SizedBox(height: DVStudioStyle.space1),
      DVStudioStyle.body(
        'HTML every page of this app carries, exactly as written: analytics and '
        'tag managers, site verification, chat widgets.',
        color: DVStudioStyle.muted,
      ),
      const SizedBox(height: DVStudioStyle.space3),
      DVStudioStyle.banner(
        tone: DVStudioStyle.warning,
        icon: Icons.warning_amber_outlined,
        child: DVStudioStyle.body(
          'This HTML runs as it is, on every page, with full access to the page '
            'and to anybody using it. Only add HTML from a source you trust.',
          color: DVStudioStyle.warning,
        ),
      ),
      if (state['pending'] == true) ...<Widget>[
        const SizedBox(height: DVStudioStyle.space3),
        DVStudioStyle.body('A saved change is waiting to be sent from the GitHub screen.',
            color: DVStudioStyle.warning),
      ],
      if (!canEdit) ...<Widget>[
        const SizedBox(height: DVStudioStyle.space3),
        DVStudioStyle.body(
          source != 'pubspec'
              ? 'This project\'s settings are written in Dart, in $source. Change the '
                  'platforms field of its config class there.'
              : 'Only the app\'s owner can change the HTML every page carries.',
          color: DVStudioStyle.muted,
        ),
      ],
      for (final DVDocumentSlot slot in DVDocumentSlot.values) ...<Widget>[
        const SizedBox(height: DVStudioStyle.space5),
        _slot(slot, canEdit),
      ],
      if (_problem != null) ...<Widget>[
        const SizedBox(height: DVStudioStyle.space3),
        DVStudioStyle.body(_problem!, color: DVStudioStyle.danger),
        for (final String line in _serverProblems) DVStudioStyle.caption(line, color: DVStudioStyle.danger),
      ],
      if (canEdit) ...<Widget>[
        const SizedBox(height: DVStudioStyle.space4),
        Wrap(
          spacing: DVStudioStyle.space2,
          runSpacing: DVStudioStyle.space2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _button('dv-studio-platforms-save', _busy ? 'Saving…' : 'Save', _busy || !_valid ? null : () => unawaited(_save()),
                primary: true),
            if (!_valid) DVStudioStyle.caption('Fix the HTML marked above to save.', color: DVStudioStyle.danger),
          ],
        ),
      ],
      if (_saved != null) ...<Widget>[
        const SizedBox(height: DVStudioStyle.space3),
        DVStudioStyle.body(_saved!, color: DVStudioStyle.success),
      ],
      const SizedBox(height: DVStudioStyle.space5),
      DVStudioStyle.heading('How every page begins and ends'),
      const SizedBox(height: DVStudioStyle.space2),
      DVStudioStyle.card(
        padding: const .all(DVStudioStyle.space3),
        child: KeyedSubtree(
          key: const ValueKey<String>('dv-studio-platforms-preview'),
          child: Semantics(
            label: 'Preview of the start and end of every page',
            child: Text(
              _preview(state),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: DVStudioStyle.ink, height: 1.4),
            ),
          ),
        ),
      ),
    ];
  }

  /// The edges of a page as the next build will write them, from what is on
  /// screen now.
  String _preview(Map<String, Object?> state) {
    final Map<Object?, Object?> files = state['files'] is Map ? state['files']! as Map : const <Object?, Object?>{};
    String slot(DVDocumentSlot which) => <String>[
          for (final _Snippet snippet in _slots[which]!)
            snippet.file ? '${files[snippet.text.trim()] ?? '<!-- ${snippet.text.trim()} -->'}'.trimRight() : snippet.text,
        ].where((String text) => text.trim().isNotEmpty).map((String text) => text.split('\n').map((String line) => '  $line').join('\n')).join('\n');
    final String head = slot(DVDocumentSlot.head);
    final String start = slot(DVDocumentSlot.bodyStart);
    final String end = slot(DVDocumentSlot.bodyEnd);
    return <String>[
      '<head>',
      '  … the tags Dartvel writes for each page …',
      if (head.isNotEmpty) head,
      '</head>',
      '<body>',
      if (start.isNotEmpty) start,
      '  … the page …',
      if (end.isNotEmpty) end,
      '</body>',
    ].join('\n');
  }

  Widget _slot(DVDocumentSlot slot, bool canEdit) {
    final List<_Snippet> snippets = _slots[slot]!;
    return DVStudioStyle.card(
      padding: const .all(DVStudioStyle.space4),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          DVStudioStyle.heading(_slotLabel(slot)),
          const SizedBox(height: DVStudioStyle.space1),
          DVStudioStyle.caption(_slotHelp(slot)),
          const SizedBox(height: DVStudioStyle.space3),
          if (snippets.isEmpty) DVStudioStyle.body('Nothing here yet.', color: DVStudioStyle.muted),
          for (int index = 0; index < snippets.length; index++) _entry(slot, index, canEdit),
          if (canEdit) ...<Widget>[
            const SizedBox(height: DVStudioStyle.space2),
            Wrap(
              spacing: DVStudioStyle.space2,
              runSpacing: DVStudioStyle.space2,
              children: <Widget>[
                _button('dv-studio-platforms-${slot.key}-add-html', 'Add HTML',
                    () => setState(() => snippets.add(_Snippet.html(''))), icon: Icons.code),
                _button('dv-studio-platforms-${slot.key}-add-file', 'Add a file from html/',
                    () => setState(() => snippets.add(_Snippet.file(''))), icon: Icons.description_outlined),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _entry(DVDocumentSlot slot, int index, bool canEdit) {
    final List<_Snippet> snippets = _slots[slot]!;
    final _Snippet snippet = snippets[index];
    final String key = 'dv-studio-platforms-${slot.key}-$index';
    final String name = '${snippet.file ? 'File' : 'HTML'} ${index + 1}, ${_slotLabel(slot).toLowerCase()}';
    final List<String> problems = _problemsOf(slot, snippet);
    return Padding(
      padding: const .only(bottom: DVStudioStyle.space3),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          DVStudioStyle.overline(snippet.file ? 'From a file' : 'HTML'),
          const SizedBox(height: DVStudioStyle.space1),
          if (canEdit)
            KeyedSubtree(
              // The position and the kind, so moving or removing one gives
              // the others fresh fields rather than another's text.
              key: ValueKey<String>(key),
              child: DVStudioTextInput(
                key: ValueKey<Object>(snippet),
                value: snippet.text,
                lines: snippet.file ? 1 : 4,
                code: true,
                icon: snippet.file ? Icons.description_outlined : null,
                placeholder: snippet.file ? 'html/head.html' : '<script src="https://…"></script>',
                semanticLabel: name,
                onChanged: (String value) => setState(() {
                  snippet.text = value;
                  _saved = null;
                }),
              ),
            )
          else
            Text(
              snippet.file ? snippet.text : snippet.text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: DVStudioStyle.ink),
            ),
          if (canEdit && snippet.text.trim().isNotEmpty)
            for (final String problem in problems) ...<Widget>[
              const SizedBox(height: DVStudioStyle.space1),
              DVStudioStyle.caption(problem, color: DVStudioStyle.danger),
            ],
          if (canEdit) ...<Widget>[
            const SizedBox(height: DVStudioStyle.space1),
            Wrap(
              spacing: DVStudioStyle.space2,
              runSpacing: DVStudioStyle.space1,
              children: <Widget>[
                if (index > 0)
                  _button('$key-up', 'Move up', () => setState(() {
                        snippets.insert(index - 1, snippets.removeAt(index));
                      }), icon: Icons.arrow_upward),
                if (index < snippets.length - 1)
                  _button('$key-down', 'Move down', () => setState(() {
                        snippets.insert(index + 1, snippets.removeAt(index));
                      }), icon: Icons.arrow_downward),
                _button('$key-remove', 'Remove', () => setState(() => snippets.removeAt(index)),
                    icon: Icons.delete_outline),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

Widget _button(String key, String label, VoidCallback? onTap, {bool primary = false, IconData? icon}) =>
    DVStudioControl(
      key: ValueKey<String>(key),
      label: label,
      enabled: onTap != null,
      onTap: onTap,
      primary: primary,
      icon: icon,
    );
