/// Studio's Components section: every component the project has, made and
/// changed on the same canvas pages are, with the props each use can set.
///
/// Free Studio, not Pro: a builder whose repeated parts have to be rebuilt
/// by hand on every page is one nobody keeps using.
library;

import 'dart:async';

import 'package:flutter/material.dart'
    show Icon, IconData, Icons, Material;
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// The Components section.
class DVStudioComponentsSection extends StatefulWidget {
  const DVStudioComponentsSection({
    super.key,
    this.store = const DVPageStore(),
    this.palette = const <DVStudioPaletteItem>[],
    this.open,
  });

  /// Where components are kept: the same store as the pages.
  final DVPageStore store;

  /// What can be put into a component; the built-in elements by default.
  final List<DVStudioPaletteItem> palette;

  /// A component to open straight away: the one a use of it asked to edit.
  final String? open;

  @override
  State<DVStudioComponentsSection> createState() =>
      _DVStudioComponentsSectionState();
}

class _DVStudioComponentsSectionState extends State<DVStudioComponentsSection> {
  List<String> _names = const <String>[];
  String _newName = '';
  String? _problem;
  DVStudioEditorController? _controller;
  List<DVStudioComponentProp> _props = <DVStudioComponentProp>[];
  bool _saving = false;
  bool _showLayers = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load().then((_) {
      final String? open = widget.open;
      if (open != null && mounted) unawaited(_openComponent(open));
    }));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<String> routes = await widget.store.routes();
    if (!mounted) return;
    setState(() {
      _names = <String>[
        for (final String route in routes) ?dvStudioComponentName(route),
      ]..sort();
    });
  }

  Future<void> _openComponent(String name) async {
    final DVPageDocument? document =
        await widget.store.load(dvStudioComponentRoute(name));
    if (!mounted || document == null) return;
    _edit(document);
  }

  void _edit(DVPageDocument document) {
    setState(() {
      _controller?.dispose();
      _controller = DVStudioEditorController(document);
      _props = dvStudioComponentPropsOf(document);
      _problem = null;
    });
  }

  /// One word, capitalised, as a data model is named: it is how a page and
  /// the exported code call it.
  static final RegExp _validName = RegExp(r'^[A-Z][A-Za-z0-9]*$');

  void _create() {
    final String name = _newName.trim();
    if (!_validName.hasMatch(name)) {
      setState(() => _problem =
          'Name it with one word starting with a capital letter, like PriceCard.');
      return;
    }
    if (_names.contains(name)) {
      unawaited(_openComponent(name));
      return;
    }
    _edit(dvStudioComponent(
      name,
      root: DVPageNode(
        type: 'box',
        properties: <String, Object?>{'padding': 16, 'spacing': 12},
      ),
    ));
  }

  Future<void> _save() async {
    final DVStudioEditorController? controller = _controller;
    if (controller == null || _saving) return;
    setState(() => _saving = true);
    try {
      final DVPageDocument document = controller.document;
      dvStudioSetComponentProps(document, _props);
      await widget.store.save(document);
      // Pages draw uses of it from the application's copy of the store.
      await DVPageStore.reload();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _problem = 'Could not save: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final DVStudioEditorController? controller = _controller;
    if (controller == null) return;
    await widget.store.delete(controller.document.route);
    await DVPageStore.reload();
    if (!mounted) return;
    setState(() {
      _controller?.dispose();
      _controller = null;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Container(
          width: 248,
          decoration: const BoxDecoration(
            color: DVStudioStyle.surface,
            border: Border(right: BorderSide(color: DVStudioStyle.line)),
          ),
          child: _list(),
        ),
        Expanded(child: _editor()),
      ],
    );
  }

  Widget _list() {
    final String? open =
        _controller == null ? null : dvStudioComponentName(_controller!.document.route);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        DVStudioStyle.panelHeader(title: 'Components', subtitle: '${_names.length}'),
        Padding(
          padding: const .all(DVStudioStyle.space3),
          child: Column(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              KeyedSubtree(
                key: const ValueKey<String>('dv-studio-component-name'),
                child: DVStudioTextInput(
                  value: _newName,
                  placeholder: 'PriceCard',
                  icon: DVStudioIcons.components,
                  onChanged: (String value) => _newName = value,
                  onSubmitted: (_) => _create(),
                ),
              ),
              const SizedBox(height: DVStudioStyle.space2),
              _control('dv-studio-component-create', 'New component', _create,
                  icon: DVStudioIcons.add, primary: true),
              if (_problem != null) ...<Widget>[
                const SizedBox(height: DVStudioStyle.space2),
                DVStudioStyle.caption(_problem!, color: DVStudioStyle.danger),
              ],
            ],
          ),
        ),
        Container(height: 1, color: DVStudioStyle.line),
        Expanded(
          child: _names.isEmpty
              ? Padding(
                  padding: const .all(DVStudioStyle.space4),
                  child: DVStudioStyle.caption(
                      'No components yet. Make one here, or select something '
                      'on a page and press Ctrl+Alt+K.'),
                )
              : ListView(
                  children: <Widget>[
                    for (final String name in _names)
                      DVStudioListRow(
                        key: ValueKey<String>('dv-studio-component-row-$name'),
                        title: name,
                        icon: DVStudioIcons.components,
                        selected: name == open,
                        onTap: () => unawaited(_openComponent(name)),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _editor() {
    final DVStudioEditorController? controller = _controller;
    if (controller == null) {
      return DVStudioStyle.emptyState(
        icon: DVStudioIcons.components,
        title: 'Make something once, use it everywhere',
        message: 'A component is a part you design once -- a card, a header, '
            'a price box -- and put on any page. Change it here and every page '
            'using it changes too.',
      );
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) => Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          _toolbar(controller),
          Expanded(
            child: Row(
              crossAxisAlignment: .stretch,
              children: <Widget>[
                Container(
                  width: 248,
                  decoration: const BoxDecoration(
                    color: DVStudioStyle.surface,
                    border: Border(right: BorderSide(color: DVStudioStyle.line)),
                  ),
                  child: Column(
                    crossAxisAlignment: .stretch,
                    children: <Widget>[
                      Padding(
                        padding: const .all(DVStudioStyle.space2),
                        child: DVStudioSegmented<bool>(
                          segments: const <DVStudioSegment<bool>>[
                            DVStudioSegment<bool>(
                                value: false, label: 'Insert', icon: DVStudioIcons.insert),
                            DVStudioSegment<bool>(
                                value: true, label: 'Layers', icon: DVStudioIcons.layers),
                          ],
                          value: _showLayers,
                          onChanged: (bool v) => setState(() => _showLayers = v),
                        ),
                      ),
                      Expanded(
                        child: _showLayers
                            ? DVStudioLayers(controller: controller)
                            : DVStudioPalette(
                                items: widget.palette, controller: controller),
                      ),
                    ],
                  ),
                ),
                Expanded(child: DVStudioCanvas(controller: controller)),
                Container(
                  width: 300,
                  decoration: const BoxDecoration(
                    color: DVStudioStyle.surface,
                    border: Border(left: BorderSide(color: DVStudioStyle.line)),
                  ),
                  child: Column(
                    crossAxisAlignment: .stretch,
                    children: <Widget>[
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 360),
                        child: SingleChildScrollView(child: _propsPanel(controller)),
                      ),
                      Container(height: 1, color: DVStudioStyle.line),
                      Expanded(child: DVStudioInspector(controller: controller)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar(DVStudioEditorController controller) {
    final String name = dvStudioComponentName(controller.document.route) ?? '';
    return Container(
      height: 44,
      padding: const .symmetric(horizontal: DVStudioStyle.space3),
      decoration: const BoxDecoration(
        color: DVStudioStyle.surface,
        border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(DVStudioIcons.components, size: 16, color: DVStudioStyle.muted),
          const SizedBox(width: DVStudioStyle.space2),
          DVStudioStyle.heading(name),
          const Spacer(),
          DVStudioIconButton(
            icon: DVStudioIcons.undo,
            tooltip: 'Undo (Ctrl+Z)',
            onTap: controller.canUndo ? controller.undo : null,
          ),
          DVStudioIconButton(
            icon: DVStudioIcons.redo,
            tooltip: 'Redo (Ctrl+Shift+Z)',
            onTap: controller.canRedo ? controller.redo : null,
          ),
          DVStudioIconButton(
            icon: DVStudioIcons.delete,
            tooltip: 'Delete this component',
            onTap: () => unawaited(_delete()),
          ),
          const SizedBox(width: DVStudioStyle.space2),
          _control(
            'dv-studio-component-save',
            _saving ? 'Saving…' : 'Save component',
            _saving ? null : () => unawaited(_save()),
            icon: DVStudioIcons.publish,
            primary: true,
          ),
        ],
      ),
    );
  }

  /// The props: what each use of this component can set for itself.
  Widget _propsPanel(DVStudioEditorController controller) {
    return Padding(
      padding: const .all(DVStudioStyle.space3),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          DVStudioStyle.overline('Props'),
          const SizedBox(height: 4),
          DVStudioStyle.caption(
            'What each page using this can change. Type {{name}} into a text, '
            'a picture\'s address or a colour to use one.',
          ),
          const SizedBox(height: DVStudioStyle.space2),
          for (int i = 0; i < _props.length; i++) _propRow(controller, i),
          _control(
            'dv-studio-component-add-prop',
            'Add a prop',
            () => setState(() => _props = <DVStudioComponentProp>[
                  ..._props,
                  DVStudioComponentProp(
                      'prop${_props.length + 1}', DVStudioPropKind.text, ''),
                ]),
            icon: DVStudioIcons.add,
          ),
        ],
      ),
    );
  }

  Widget _propRow(DVStudioEditorController controller, int i) {
    final DVStudioComponentProp prop = _props[i];
    void replace(DVStudioComponentProp next) =>
        setState(() => _props = <DVStudioComponentProp>[..._props]..[i] = next);
    final String? selected = controller.selectedId;
    return Padding(
      padding: const .only(bottom: DVStudioStyle.space3),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: KeyedSubtree(
                  key: ValueKey<String>('dv-studio-component-prop-name-$i'),
                  child: DVStudioTextInput(
                    value: prop.name,
                    placeholder: 'name',
                    onChanged: (String v) =>
                        replace(DVStudioComponentProp(v.trim(), prop.kind, prop.value)),
                  ),
                ),
              ),
              DVStudioIconButton(
                icon: DVStudioIcons.delete,
                tooltip: 'Remove this prop',
                onTap: () => setState(
                    () => _props = <DVStudioComponentProp>[..._props]..removeAt(i)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: .scaleDown,
            alignment: .centerLeft,
            child: DVStudioSegmented<DVStudioPropKind>(
              segments: <DVStudioSegment<DVStudioPropKind>>[
                for (final DVStudioPropKind kind in DVStudioPropKind.values)
                  DVStudioSegment<DVStudioPropKind>(
                    value: kind,
                    icon: _kindIcon(kind),
                    tooltip: kind.label,
                  ),
              ],
              value: prop.kind,
              onChanged: (DVStudioPropKind kind) =>
                  replace(DVStudioComponentProp(prop.name, kind, prop.value)),
            ),
          ),
          const SizedBox(height: 4),
          if (prop.kind == DVStudioPropKind.action)
            _control(
              'dv-studio-component-prop-use-$i',
              'Use for the selected element\'s tap',
              selected == null
                  ? null
                  : () => controller.setAction(
                      selected, <String, Object?>{'type': 'prop', 'name': prop.name}),
            )
          else
            DVStudioTextInput(
              value: '${prop.value ?? ''}',
              label: 'Default',
              onChanged: (String v) =>
                  replace(DVStudioComponentProp(prop.name, prop.kind, v)),
            ),
        ],
      ),
    );
  }

  static IconData _kindIcon(DVStudioPropKind kind) => switch (kind) {
        DVStudioPropKind.text => Icons.text_fields,
        DVStudioPropKind.image => Icons.image_outlined,
        DVStudioPropKind.colour => Icons.palette_outlined,
        DVStudioPropKind.action => Icons.touch_app_outlined,
      };
}

Widget _control(String key, String label, VoidCallback? onTap,
    {IconData? icon, bool primary = false}) {
  return GestureDetector(
    key: ValueKey<String>(key),
    onTap: onTap,
    child: MouseRegion(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        child: DVStudioStyle.control(label,
            enabled: onTap != null, primary: primary, icon: icon),
      ),
    ),
  );
}

/// Asks for a name for a new component; null when somebody thinks better of
/// it.
Future<String?> dvStudioAskComponentName(BuildContext context) {
  String name = '';
  final RegExp valid = RegExp(r'^[A-Z][A-Za-z0-9]*$');
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cancel',
    barrierColor: const Color(0x33000000),
    pageBuilder: (BuildContext dialog, _, _) => Center(
      child: Material(
        color: DVStudioStyle.surface,
        borderRadius: .circular(DVStudioStyle.radiusLarge),
        elevation: 8,
        child: SizedBox(
          width: 380,
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter set) {
              final bool ok = valid.hasMatch(name.trim());
              return Padding(
                padding: const .all(DVStudioStyle.space5),
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .stretch,
                  children: <Widget>[
                    DVStudioStyle.heading('Make a component'),
                    const SizedBox(height: 4),
                    DVStudioStyle.caption(
                        'The selection becomes a part you can put on any page. '
                        'Name it with one word, like PriceCard.'),
                    const SizedBox(height: DVStudioStyle.space3),
                    KeyedSubtree(
                      key: const ValueKey<String>('dv-studio-make-component-name'),
                      child: DVStudioTextInput(
                        value: '',
                        placeholder: 'PriceCard',
                        onChanged: (String v) => set(() => name = v),
                        onSubmitted: (_) {
                          if (ok) Navigator.of(dialog).pop(name.trim());
                        },
                      ),
                    ),
                    const SizedBox(height: DVStudioStyle.space3),
                    Align(
                      alignment: .centerRight,
                      child: _control(
                        'dv-studio-make-component-confirm',
                        'Make component',
                        ok ? () => Navigator.of(dialog).pop(name.trim()) : null,
                        primary: true,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
