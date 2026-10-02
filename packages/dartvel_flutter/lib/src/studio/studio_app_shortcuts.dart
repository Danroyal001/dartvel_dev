/// Keyboard shortcuts for the application, set in Studio without code.
///
/// Studio keeps them as [DVShortcut] JSON -- the same definitions an
/// application writes for `DVShortcutScope.commands` -- in a document at
/// `/_dartvel/shortcuts`, beside the pages, so they are stored, published and
/// delivered the way a page is. Every page's shell answers them. A command
/// Studio writes is a page to go to, `go:/menu`; a definition that does not
/// parse is left out rather than breaking every page.
library;

import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// Where the application's shortcuts are kept.
const String dvStudioShortcutsRoute = '/_dartvel/shortcuts';

/// The command that opens [route].
String dvStudioGoCommand(String route) => 'go:$route';

/// The page a `go:` command opens, or null for another command.
String? dvStudioGoRoute(String command) =>
    command.startsWith('go:') && command.length > 3 ? command.substring(3) : null;

/// A document holding [shortcuts].
DVPageDocument dvStudioAppShortcutsDocument(List<DVShortcut> shortcuts) =>
    DVPageDocument(
      route: dvStudioShortcutsRoute,
      title: 'Keyboard shortcuts',
      root: DVPageNode(type: 'box', properties: <String, Object?>{
        'shortcuts': <Object?>[for (final DVShortcut s in shortcuts) s.toJson()],
      }),
    );

/// The shortcuts in [document], leaving out any that do not parse.
List<DVShortcut> dvStudioAppShortcutsOf(DVPageDocument? document) {
  final Object? raw = document?.root.properties['shortcuts'];
  if (raw is! List) return const <DVShortcut>[];
  final List<DVShortcut> out = <DVShortcut>[];
  for (final Object? entry in raw) {
    if (entry is! Map) continue;
    try {
      out.add(DVShortcut.fromJson(entry.cast<String, Object?>()));
    } on Object {
      // Written by hand, or by an older Studio: skipped, not fatal.
    }
  }
  return out;
}

/// [child] answering the application's Studio shortcuts, when it has any.
///
/// The page shell puts every page under this. With no shortcuts it is
/// [child] and nothing else, so an application that never set one has not a
/// single widget more.
class DVStudioAppShortcuts extends StatefulWidget {
  const DVStudioAppShortcuts({super.key, required this.child});

  final Widget child;

  @override
  State<DVStudioAppShortcuts> createState() => _DVStudioAppShortcutsState();
}

class _DVStudioAppShortcutsState extends State<DVStudioAppShortcuts> {
  StreamSubscription<String>? _changes;

  @override
  void initState() {
    super.initState();
    if (!DVPageStore.isPrimed) {
      unawaited(DVPageStore.prime().then((_) {
        if (mounted) setState(() {});
      }));
    }
    _changes = DVPageStore.changes.listen((String route) {
      if (route == dvStudioShortcutsRoute && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<DVShortcut> all =
        dvStudioAppShortcutsOf(DVPageStore.cached(dvStudioShortcutsRoute));
    final Map<String, VoidCallback> actions = <String, VoidCallback>{};
    final List<DVShortcut> usable = <DVShortcut>[];
    final Set<String> keys = <String>{};
    for (final DVShortcut shortcut in all) {
      final String? route = dvStudioGoRoute(shortcut.command);
      // Two for one key would be a conflict the scope refuses; the first
      // stands.
      if (route == null || !keys.add(shortcut.keys.toLowerCase())) continue;
      usable.add(shortcut);
      actions[shortcut.command] = DV.Navigation.to(DVRouteTarget(route));
    }
    if (usable.isEmpty) return widget.child;
    return DVShortcutScope.commands(
      usable,
      actions: actions,
      child: widget.child,
    );
  }
}

/// Studio's Shortcuts section: the keys the application answers, each with
/// a name and the page it opens.
class DVStudioShortcutsSection extends StatefulWidget {
  const DVStudioShortcutsSection({super.key, this.store = const DVPageStore()});

  final DVPageStore store;

  @override
  State<DVStudioShortcutsSection> createState() =>
      _DVStudioShortcutsSectionState();
}

class _Row {
  _Row(this.keys, this.label, this.page);
  String keys;
  String label;
  String page;
  String? problem;
}

class _DVStudioShortcutsSectionState extends State<DVStudioShortcutsSection> {
  List<_Row> _rows = <_Row>[];
  bool _saving = false;
  String? _saved;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final DVPageDocument? document =
        await widget.store.load(dvStudioShortcutsRoute);
    if (!mounted) return;
    setState(() => _rows = <_Row>[
          for (final DVShortcut s in dvStudioAppShortcutsOf(document))
            _Row(s.keys, s.label, dvStudioGoRoute(s.command) ?? ''),
        ]);
  }

  Future<void> _save() async {
    if (_saving) return;
    final List<DVShortcut> shortcuts = <DVShortcut>[];
    bool ok = true;
    final Set<String> seen = <String>{};
    for (final _Row row in _rows) {
      row.problem = null;
      final String page = row.page.trim();
      final DVShortcut shortcut = DVShortcut(
        keys: row.keys.trim(),
        command: dvStudioGoCommand(page.startsWith('/') ? page : '/$page'),
        label: row.label.trim().isEmpty ? 'Go to $page' : row.label.trim(),
      );
      try {
        shortcut.validate();
      } on Object {
        row.problem = 'Keys like Ctrl+M, Shift+F or Alt+1.';
        ok = false;
        continue;
      }
      if (!seen.add(shortcut.keys.toLowerCase())) {
        row.problem = 'Another shortcut already uses ${shortcut.keys}.';
        ok = false;
        continue;
      }
      shortcuts.add(shortcut);
    }
    if (!ok) {
      setState(() => _saved = null);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.store.save(dvStudioAppShortcutsDocument(shortcuts));
      await DVPageStore.reload();
      if (mounted) setState(() => _saved = 'Saved. The app answers them now.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DVStudioStyle.canvas,
      child: ListView(
        padding: const .all(DVStudioStyle.space6),
        children: <Widget>[
          DVStudioStyle.title('Keyboard shortcuts'),
          const SizedBox(height: DVStudioStyle.space1),
          DVStudioStyle.body(
            'Keys that open a page of your app from anywhere in it, like '
            'Ctrl+M for the menu. People can press ? to see them all.',
            color: DVStudioStyle.muted,
          ),
          const SizedBox(height: DVStudioStyle.space4),
          for (int i = 0; i < _rows.length; i++) _row(i),
          Row(
            children: <Widget>[
              _button('dv-studio-shortcut-add', 'Add a shortcut',
                  () => setState(() => _rows = <_Row>[..._rows, _Row('', '', '/')]),
                  icon: DVStudioIcons.add),
              const SizedBox(width: DVStudioStyle.space2),
              _button('dv-studio-shortcuts-save', _saving ? 'Saving…' : 'Save',
                  _saving ? null : () => unawaited(_save()),
                  icon: DVStudioIcons.publish, primary: true),
              if (_saved != null) ...<Widget>[
                const SizedBox(width: DVStudioStyle.space3),
                DVStudioStyle.caption(_saved!, color: DVStudioStyle.success),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(int i) {
    final _Row row = _rows[i];
    Widget field(String key, String hint, String value, void Function(String) set,
            {int flex = 1}) =>
        Expanded(
          flex: flex,
          child: KeyedSubtree(
            key: ValueKey<String>(key),
            child: DVStudioTextInput(
              value: value,
              placeholder: hint,
              onChanged: (String v) => set(v),
            ),
          ),
        );
    return Padding(
      padding: const .only(bottom: DVStudioStyle.space3),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              field('dv-studio-shortcut-keys-$i', 'Ctrl+M', row.keys,
                  (String v) => row.keys = v),
              const SizedBox(width: DVStudioStyle.space2),
              field('dv-studio-shortcut-label-$i', 'What it is called', row.label,
                  (String v) => row.label = v, flex: 2),
              const SizedBox(width: DVStudioStyle.space2),
              field('dv-studio-shortcut-page-$i', 'Page it opens: /menu', row.page,
                  (String v) => row.page = v, flex: 2),
              DVStudioIconButton(
                icon: DVStudioIcons.delete,
                tooltip: 'Remove this shortcut',
                onTap: () => setState(() => _rows = <_Row>[..._rows]..removeAt(i)),
              ),
            ],
          ),
          if (row.problem != null)
            Padding(
              key: ValueKey<String>('dv-studio-shortcut-problem-$i'),
              padding: const .only(top: 4),
              child: DVStudioStyle.caption(row.problem!, color: DVStudioStyle.danger),
            ),
        ],
      ),
    );
  }
}

Widget _button(String key, String label, VoidCallback? onTap,
    {IconData? icon, bool primary = false}) {
  return DVStudioControl(
    key: ValueKey<String>(key),
    label: label,
    enabled: onTap != null,
    onTap: onTap,
    primary: primary,
    icon: icon ?? Icons.add,
  );
}
