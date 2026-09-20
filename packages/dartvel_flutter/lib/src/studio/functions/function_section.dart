// The Studio function builders: Frontend and Backend, one builder for both.
//
// Pro, per the tier table in docs/business-model.md: Studio's page builder and
// every generated admin surface are free forever, and this is one of the
// things listed opposite them. It lived in dartvel_core and dartvel_flutter,
// which meant the whole of it shipped in the open-source framework.
//
// It attaches through DVStudioSection, so free Studio does not know it exists
// and a build without it has no Frontend tab, and a Backend that lists the
// app's functions, rather than a tab that opens onto nothing.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../dartvel_flutter.dart';

/// The Frontend and Backend sections, for registering with
/// [DVStudioScreen]: a function built in each, with the same builder.
///
/// ```dart
/// DVStudioScreen(sections: dvFunctionStudioSections())
/// ```
///
/// Backend takes the id of free Studio's list of backend functions, so it
/// stands in that list's place rather than beside it.
List<DVStudioSection> dvFunctionStudioSections({
  List<DVWorkflowPaletteItem> palette = const <DVWorkflowPaletteItem>[],
  DVFunctionStore? store,
  DVCodeFunctions? written,
}) =>
    <DVStudioSection>[
      for (final DVWorkflowSide side in DVWorkflowSide.values)
        dvWorkflowStudioSection(
          palette: palette,
          side: side,
          store: store,
          written: side == DVWorkflowSide.backend ? written : null,
        ),
    ];

/// The backend functions a project wrote in code, for the Backend section to
/// list beside the ones built here. Each is `{name, path, source}`.
typedef DVCodeFunctions = Future<List<Map<String, Object?>>> Function();

/// One side's section: Frontend or Backend.
DVStudioSection dvWorkflowStudioSection({
  List<DVWorkflowPaletteItem> palette = const <DVWorkflowPaletteItem>[],
  DVWorkflowSide side = DVWorkflowSide.backend,
  DVFunctionStore? store,
  DVCodeFunctions? written,
}) {
  return DVStudioSection(
    id: side == DVWorkflowSide.backend ? 'functions' : 'frontend',
    label: side.label,
    icon: side == DVWorkflowSide.backend
        ? DVStudioIcons.workflows
        : Icons.touch_app_outlined,
    build: (BuildContext context) => _DVStudioWorkflowsSection(
      key: ValueKey<String>('dv-studio-workflows-${side.name}'),
      palette: palette,
      side: side,
      store: store ?? const DVWorkflowStore(),
      written: written,
    ),
  );
}

/// One side's functions: the same choose/create/deploy/delete cycle over
/// workflow documents.
class _DVStudioWorkflowsSection extends StatefulWidget {
  final List<DVWorkflowPaletteItem> palette;
  final DVWorkflowSide side;
  final DVFunctionStore store;
  final DVCodeFunctions? written;

  const _DVStudioWorkflowsSection({
    super.key,
    required this.palette,
    required this.side,
    required this.store,
    this.written,
  });

  @override
  State<_DVStudioWorkflowsSection> createState() =>
      _DVStudioWorkflowsSectionState();
}

class _DVStudioWorkflowsSectionState extends State<_DVStudioWorkflowsSection> {
  DVFunctionStore get _store => widget.store;

  List<String> _names = <String>[];
  DVWorkflowEditorController? _controller;
  String? _error;

  /// Why the last Deploy did not happen, shown over the builder.
  String? _problem;
  bool _loading = true;
  bool _saving = false;
  bool _showingCode = false;
  String _newName = '';

  /// "Frontend functions" or "Backend functions".
  String get _kind => '${widget.side.label} functions';

  @override
  void initState() {
    super.initState();
    unawaited(_loadNames());
    unawaited(_loadWritten());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// The backend functions the project wrote in code: listed, not editable
  /// here, because they live in files the developer owns.
  List<Map<String, Object?>> _written = <Map<String, Object?>>[];

  /// The one being looked at, or null.
  Map<String, Object?>? _writtenOpen;

  Future<void> _loadWritten() async {
    final DVCodeFunctions? written = widget.written;
    if (written == null) return;
    try {
      final List<Map<String, Object?>> found = await written();
      if (mounted) setState(() => _written = found);
    } catch (_) {
      // The manifest is missing on a build that has none. The builder's own
      // functions are still listed.
    }
  }

  Future<void> _loadNames() async {
    try {
      final names = await _store.names(side: widget.side);
      if (!mounted) return;
      setState(() {
        _names = names;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _open(String name) async {
    // A load that threw used to leave the panel reading "No function open"
    // beside a list with that very function in it, so a document that will
    // not parse was indistinguishable from a tap that missed. Found while
    // photographing Studio: the Frontend list had the function, the tap
    // landed, and the builder stayed empty in every capture.
    try {
      final document = await _store.load(name);
      if (!mounted) return;
      if (document == null) {
        setState(() => _problem = 'There is no function called $name any '
            'more. Reload the list.');
        return;
      }
      _select(document);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _problem = 'Could not open $name: $error');
    }
  }

  void _select(DVWorkflowDocument document) {
    setState(() {
      _controller?.dispose();
      _controller = DVWorkflowEditorController(document, store: _store);
      _problem = null;
      _showingCode = false;
    });
  }

  Future<void> _create() async {
    final name = _newName.trim();
    if (name.isEmpty) return;
    // Same bargain as pages: opening the stored function instead of a blank
    // one, so creating over an existing name cannot erase it on first save.
    if (_names.contains(name)) {
      unawaited(_open(name));
      return;
    }
    // Both sides are functions of one app, so a name the other side has is
    // taken: exporting both would declare it twice.
    final DVWorkflowDocument? other = await _store.load(name);
    if (!mounted) return;
    if (other != null) {
      setState(() => _problem = 'There is already a '
          '${other.side.label.toLowerCase()} function called $name.');
      return;
    }
    _select(DVWorkflowDocument(name: name, side: widget.side));
  }

  Future<void> _publish() async {
    final controller = _controller;
    if (controller == null || _saving) return;
    // An input with no type is checked by nothing, so a workflow with one
    // is not deployed: the backend function it becomes would take anything.
    final List<String> untyped = controller.document.untyped;
    if (untyped.isNotEmpty) {
      setState(() => _problem = 'Give ${untyped.join(', ')} a type before '
          'deploying. Select nothing on the canvas to see the inputs.');
      return;
    }
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      await controller.save();
      await _loadNames();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final controller = _controller;
    if (controller == null) return;
    await _store.delete(controller.document.name);
    if (!mounted) return;
    setState(() {
      _controller?.dispose();
      _controller = null;
    });
    await _loadNames();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return DVStudioStyle.placeholder('Loading ${_kind.toLowerCase()}…');
    }
    final controller = _controller;
    return DVStudioStyle.panes(
      list: _workflowList(),
      detail: controller != null
          ? _builder(controller)
          : _writtenOpen != null
              ? _writtenDetail(_writtenOpen!)
              : _nothingOpen(),
    );
  }

  /// What a function written in code is called in the list: the method and
  /// the address it answers, or its name when the manifest has no address.
  static String _codeTitle(Map<String, Object?> fn) {
    final String path = '${fn['path'] ?? ''}';
    if (path.isEmpty) return '${fn['name'] ?? ''}';
    final String method = '${fn['method'] ?? ''}'.toUpperCase();
    return method.isEmpty ? path : '$method $path';
  }

  /// A function the project wrote in code: what it is and where it lives.
  /// Studio does not edit it -- the file is the developer's.
  Widget _writtenDetail(Map<String, Object?> fn) {
    return DVStudioSurface(
      color: DVStudioStyle.canvas,
      child: Padding(
        padding: const EdgeInsets.all(DVStudioStyle.space6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DVStudioStyle.title('${fn['name']}'),
            const SizedBox(height: DVStudioStyle.space2),
            for (final String field in const <String>['method', 'path', 'source'])
              if (fn[field] != null && '${fn[field]}'.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: DVStudioStyle.space1),
                  child: DVStudioStyle.caption('${fn[field]}'),
                ),
            const SizedBox(height: DVStudioStyle.space4),
            DVStudioStyle.banner(
              tone: DVStudioStyle.accent,
              icon: Icons.code,
              child: Text(
                'Written in your project, so it is edited there. Functions '
                'built here appear above it.',
                style: DVStudioStyle.bannerText(DVStudioStyle.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nothingOpen() {
    return DVStudioSurface(
      color: DVStudioStyle.canvas,
      child: DVStudioStyle.emptyState(
        icon: DVStudioIcons.workflows,
        title: 'No function open',
        message: 'Select or create a function to edit.',
      ),
    );
  }

  Widget _workflowList() {
    final String? open = _controller?.document.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DVStudioStyle.panelHeader(
          title: _kind,
          subtitle: '${_names.length}',
        ),
        // Creating comes first, above the list: a new workflow is the
        // commonest thing to do here, and the field is where the eye lands.
        Padding(
          padding: const EdgeInsets.all(DVStudioStyle.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DVStudioTextInput(
                icon: DVStudioIcons.add,
                placeholder: 'New function name',
                onChanged: (String value) => _newName = value,
                onSubmitted: (_) => unawaited(_create()),
              ),
              const SizedBox(height: DVStudioStyle.space2),
              GestureDetector(
                key: const ValueKey<String>('dv-studio-function-create'),
                onTap: () => unawaited(_create()),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: DVStudioStyle.control(
                    'Create function',
                    enabled: true,
                    primary: true,
                    icon: DVStudioIcons.add,
                  ),
                ),
              ),
              // A name the other side has: said here, since with nothing
              // open there is no builder to say it over.
              if (_problem != null && _controller == null) ...<Widget>[
                const SizedBox(height: DVStudioStyle.space2),
                DVStudioStyle.caption(_problem!, color: DVStudioStyle.danger),
              ],
            ],
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: DVStudioStyle.line)),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: DVStudioStyle.space2),
            children: <Widget>[
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(DVStudioStyle.space3),
                  child: DVStudioStyle.banner(
                    tone: DVStudioStyle.danger,
                    icon: Icons.error_outline,
                    child: Text('Could not read ${_kind.toLowerCase()}: $_error',
                        style: DVStudioStyle.bannerText(DVStudioStyle.danger)),
                  ),
                ),
              for (final String name in _names)
                DVStudioListRow(
                  key: ValueKey<String>('dv-studio-function-$name'),
                  title: name,
                  icon: DVStudioIcons.workflows,
                  selected: name == open,
                  onTap: () => _open(name),
                ),
              if (_names.isEmpty && _error == null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DVStudioStyle.space4,
                    vertical: DVStudioStyle.space3,
                  ),
                  child: DVStudioStyle.caption('No ${_kind.toLowerCase()} yet.'),
                ),
              if (_written.isNotEmpty) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(DVStudioStyle.space4,
                      DVStudioStyle.space4, DVStudioStyle.space4, 0),
                  child: DVStudioStyle.overline('In your code'),
                ),
                for (final Map<String, Object?> fn in _written)
                  DVStudioListRow(
                    key: ValueKey<String>(
                        'dv-studio-code-function-${fn['path'] ?? fn['name']}'),
                    // The address, not the file name: every [id].get.dart is
                    // called "id", and a list of those says nothing about
                    // which is which.
                    title: _codeTitle(fn),
                    subtitle: '${fn['source'] ?? ''}',
                    icon: DVStudioIcons.code,
                    selected: identical(fn, _writtenOpen),
                    onTap: () => setState(() {
                      _writtenOpen = fn;
                      _controller?.dispose();
                      _controller = null;
                    }),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _builder(DVWorkflowEditorController controller) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _toolbar(controller),
          if (_problem != null)
            Container(
              key: const ValueKey<String>('dv-studio-function-problem'),
              color: DVStudioStyle.danger.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(
                  horizontal: DVStudioStyle.space4, vertical: DVStudioStyle.space2),
              child: DVStudioStyle.caption(_problem!, color: DVStudioStyle.danger),
            ),
          Expanded(
            child: _showingCode ? _code(controller) : _editor(controller),
          ),
        ],
      ),
    );
  }

  Widget _editor(DVWorkflowEditorController controller) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget palette = Container(
          decoration: const BoxDecoration(
            color: DVStudioStyle.surface,
            border: Border(right: BorderSide(color: DVStudioStyle.line)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DVStudioStyle.space3),
            child: DVWorkflowPalette(items: widget.palette),
          ),
        );
        final Widget canvas = Container(
          color: DVStudioStyle.canvas,
          child: DVWorkflowCanvas(controller: controller),
        );
        final Widget inspector = Container(
          decoration: const BoxDecoration(
            color: DVStudioStyle.surface,
            border: Border(left: BorderSide(color: DVStudioStyle.line)),
          ),
          child: DVWorkflowInspector(controller: controller),
        );
        // Fixed side panels where there is room for a canvas between them,
        // proportional ones where there is not: fixed panels in a narrow
        // window squeeze the canvas to nothing before they give up a pixel.
        final bool wide = constraints.maxWidth >= 900;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: wide
              ? <Widget>[
                  SizedBox(width: 220, child: palette),
                  Expanded(child: canvas),
                  SizedBox(width: 300, child: inspector),
                ]
              : <Widget>[
                  Expanded(flex: 2, child: palette),
                  Expanded(flex: 5, child: canvas),
                  Expanded(flex: 3, child: inspector),
                ],
        );
      },
    );
  }

  /// The exported Dart, or why there is none yet.
  static String _source(DVWorkflowEditorController controller) {
    try {
      return controller.viewCode();
    } on DVWorkflowException catch (error) {
      return '// Not exported yet: ${error.message}';
    }
  }

  Widget _code(DVWorkflowEditorController controller) {
    return Container(
      color: const Color(0xFF15151C),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DVStudioStyle.space5),
        child: Text(
          _source(controller),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12.5,
            height: 1.55,
            color: Color(0xFFE4E4EE),
          ),
        ),
      ),
    );
  }

  Widget _toolbar(DVWorkflowEditorController controller) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: DVStudioStyle.space3),
      decoration: const BoxDecoration(
        color: DVStudioStyle.surface,
        border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(DVStudioIcons.workflows,
              size: 16, color: DVStudioStyle.muted),
          const SizedBox(width: DVStudioStyle.space2),
          Flexible(
            child: Text(
              controller.document.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DVStudioStyle.ink,
              ),
            ),
          ),
          if (controller.canUndo) ...<Widget>[
            const SizedBox(width: DVStudioStyle.space2),
            DVStudioStyle.badge('Edited', tone: DVStudioStyle.warning),
          ],
          const Spacer(),
          DVStudioIconButton(
            key: const ValueKey<String>('dv-studio-function-undo'),
            icon: DVStudioIcons.undo,
            tooltip: 'Undo',
            onTap: controller.canUndo ? controller.undo : null,
          ),
          DVStudioIconButton(
            key: const ValueKey<String>('dv-studio-function-redo'),
            icon: DVStudioIcons.redo,
            tooltip: 'Redo',
            onTap: controller.canRedo ? controller.redo : null,
          ),
          DVStudioIconButton(
            key: const ValueKey<String>('dv-studio-function-view-code'),
            icon: _showingCode ? DVStudioIcons.design : DVStudioIcons.code,
            tooltip: _showingCode ? 'Back to the canvas' : 'View code',
            selected: _showingCode,
            onTap: () => setState(() => _showingCode = !_showingCode),
          ),
          DVStudioIconButton(
            key: const ValueKey<String>('dv-studio-function-delete'),
            icon: DVStudioIcons.delete,
            tooltip: 'Delete workflow',
            onTap: _delete,
          ),
          Container(
            width: 1,
            height: 20,
            margin:
                const EdgeInsets.symmetric(horizontal: DVStudioStyle.space2),
            color: DVStudioStyle.line,
          ),
          GestureDetector(
            key: const ValueKey<String>('dv-studio-function-deploy'),
            onTap: _saving ? null : _publish,
            child: MouseRegion(
              cursor: _saving
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click,
              child: DVStudioStyle.control(
                _saving ? 'Deploying…' : 'Deploy',
                enabled: !_saving,
                primary: true,
                icon: DVStudioIcons.publish,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
