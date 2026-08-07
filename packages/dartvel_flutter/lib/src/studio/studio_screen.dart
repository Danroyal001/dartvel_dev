import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// The Studio admin surface: the section switcher, the page builder and the
/// workflow builder, assembled.
///
/// The palettes, canvases and inspectors each edit one document; this is what
/// chooses which document, creates new ones, publishes them, and reverts one
/// to its compiled form. Without it the builders have no entry point in a
/// running application.
class DVStudioScreen extends StatefulWidget {
  /// The store page documents are read from and published to.
  final DVPageStore store;

  /// Widget palette entries, defaulting to the Dartvel primitives.
  final List<DVStudioPaletteItem> palette;

  /// Workflow step palette entries, defaulting to the four step types.
  final List<DVWorkflowPaletteItem> workflowPalette;

  const DVStudioScreen({
    super.key,
    this.store = const DVPageStore(),
    this.palette = const <DVStudioPaletteItem>[],
    this.workflowPalette = const <DVWorkflowPaletteItem>[],
  });

  @override
  State<DVStudioScreen> createState() => _DVStudioScreenState();
}

enum _DVStudioSection { pages, workflows }

class _DVStudioScreenState extends State<DVStudioScreen> {
  _DVStudioSection _section = _DVStudioSection.pages;

  @override
  Widget build(BuildContext context) {
    return DVBox.list(<Widget>[
      DVBox.wrapLine(<Widget>[
        _tab('Pages', _DVStudioSection.pages),
        _tab('Workflows', _DVStudioSection.workflows),
      ]),
      Expanded(
        child: switch (_section) {
          // Keyed per section so switching away disposes the controller
          // rather than leaving an edit of one kind live under the other.
          _DVStudioSection.pages => _DVStudioPagesSection(
              key: const ValueKey<String>('dv-studio-pages'),
              store: widget.store,
              palette: widget.palette,
            ),
          _DVStudioSection.workflows => _DVStudioWorkflowsSection(
              key: const ValueKey<String>('dv-studio-workflows'),
              palette: widget.workflowPalette,
            ),
        },
      ),
    ]);
  }

  Widget _tab(String label, _DVStudioSection section) {
    return GestureDetector(
      key: ValueKey<String>('dv-studio-section-${section.name}'),
      onTap: () => setState(() => _section = section),
      child: DVText(label).modifier(
        const DVModifier().fontWeight(
          _section == section ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

/// Page management: choose a page, create one, publish it, or revert a route
/// to the page the app was compiled with.
class _DVStudioPagesSection extends StatefulWidget {
  final DVPageStore store;
  final List<DVStudioPaletteItem> palette;

  const _DVStudioPagesSection({
    super.key,
    required this.store,
    required this.palette,
  });

  @override
  State<_DVStudioPagesSection> createState() => _DVStudioPagesSectionState();
}

class _DVStudioPagesSectionState extends State<_DVStudioPagesSection> {
  List<String> _routes = <String>[];
  DVStudioEditorController? _controller;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _showingCode = false;
  String _newRoute = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadRoutes());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadRoutes() async {
    try {
      final routes = await widget.store.routes();
      if (!mounted) return;
      setState(() {
        _routes = routes;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      // A missing database is the normal state of a fresh app, but reporting
      // it as an empty page list would look like the pages were deleted.
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _open(String route) async {
    final document = await widget.store.load(route);
    if (!mounted || document == null) return;
    _select(document);
  }

  void _select(DVPageDocument document) {
    setState(() {
      _controller?.dispose();
      _controller = DVStudioEditorController(document);
      _showingCode = false;
    });
  }

  void _create() {
    final route = _newRoute.trim();
    if (route.isEmpty) return;
    // Editing a route that already has a document would otherwise start from
    // a blank page and overwrite it on the first save.
    if (_routes.contains(route)) {
      unawaited(_open(route));
      return;
    }
    _select(DVPageDocument(route: route, title: route));
  }

  Future<void> _publish() async {
    final controller = _controller;
    if (controller == null || _saving) return;
    setState(() => _saving = true);
    try {
      await controller.save();
      await _loadRoutes();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Removes the stored document, which restores the compiled page for that
  /// route. Deleting an edit is how an edit is reverted.
  Future<void> _revert() async {
    final controller = _controller;
    if (controller == null) return;
    await widget.store.delete(controller.document.route);
    if (!mounted) return;
    setState(() {
      _controller?.dispose();
      _controller = null;
    });
    await _loadRoutes();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const DVText('Loading pages…');
    final controller = _controller;
    return DVBox.row(<Widget>[
      SizedBox(width: 220, child: _pageList()),
      if (controller != null)
        Expanded(child: _builder(controller))
      else
        const Expanded(child: DVText('Select or create a page to edit.')),
    ]);
  }

  Widget _pageList() {
    return DVBox.list(<Widget>[
      const DVText('Pages')
          .modifier(const DVModifier().fontSize(20).fontWeight(FontWeight.bold)),
      if (_error != null) DVText('Could not read pages: $_error'),
      for (final route in _routes)
        GestureDetector(
          key: ValueKey<String>('dv-studio-route-$route'),
          onTap: () => _open(route),
          child: DVText(route),
        ),
      if (_routes.isEmpty && _error == null)
        const DVText('No stored pages yet.'),
      _DVStudioTextField(
        label: 'new route',
        value: _newRoute,
        onChanged: (String value) => _newRoute = value,
      ),
      GestureDetector(
        key: const ValueKey<String>('dv-studio-create'),
        onTap: _create,
        child: const DVText('Create page'),
      ),
    ]);
  }

  Widget _builder(DVStudioEditorController controller) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => DVBox.list(<Widget>[
        _toolbar(controller),
        if (_showingCode)
          DVText(controller.document.toDartSource())
        else
          // Proportional rather than fixed: the palette and inspector have to
          // survive a narrow window, and fixed sidebars plus an expanded
          // canvas overflow before the canvas ever gives up space.
          DVBox.row(<Widget>[
            Expanded(flex: 2, child: DVStudioPalette(items: widget.palette)),
            Expanded(flex: 5, child: DVStudioCanvas(controller: controller)),
            Expanded(flex: 3, child: DVStudioInspector(controller: controller)),
          ]),
      ]),
    );
  }

  Widget _toolbar(DVStudioEditorController controller) {
    // Wraps rather than rows: six actions plus a route name do not fit a
    // narrow editor pane, and a toolbar that overflows hides the action that
    // fell off the end.
    return DVBox.wrapLine(<Widget>[
      DVText(controller.document.route)
          .modifier(const DVModifier().fontSize(18).fontWeight(FontWeight.bold)),
      _action('Undo', controller.canUndo ? controller.undo : null,
          key: 'dv-studio-undo'),
      _action('Redo', controller.canRedo ? controller.redo : null,
          key: 'dv-studio-redo'),
      _action(_showingCode ? 'Design' : 'View code',
          () => setState(() => _showingCode = !_showingCode),
          key: 'dv-studio-view-code'),
      _action(_saving ? 'Publishing…' : 'Publish',
          _saving ? null : _publish,
          key: 'dv-studio-publish'),
      _action('Revert to compiled', _revert, key: 'dv-studio-revert'),
    ]);
  }
}

/// Backend function management: the same choose/create/publish/delete cycle
/// over workflow documents.
class _DVStudioWorkflowsSection extends StatefulWidget {
  final List<DVWorkflowPaletteItem> palette;

  const _DVStudioWorkflowsSection({super.key, required this.palette});

  @override
  State<_DVStudioWorkflowsSection> createState() =>
      _DVStudioWorkflowsSectionState();
}

class _DVStudioWorkflowsSectionState extends State<_DVStudioWorkflowsSection> {
  static const DVWorkflowStore _store = DVWorkflowStore();

  List<String> _names = <String>[];
  DVWorkflowEditorController? _controller;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _showingCode = false;
  String _newName = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadNames());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadNames() async {
    try {
      final names = await _store.names();
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
    final document = await _store.load(name);
    if (!mounted || document == null) return;
    _select(document);
  }

  void _select(DVWorkflowDocument document) {
    setState(() {
      _controller?.dispose();
      _controller = DVWorkflowEditorController(document);
      _showingCode = false;
    });
  }

  void _create() {
    final name = _newName.trim();
    if (name.isEmpty) return;
    // Same bargain as pages: opening the stored workflow instead of a blank
    // one, so creating over an existing name cannot erase it on first save.
    if (_names.contains(name)) {
      unawaited(_open(name));
      return;
    }
    _select(DVWorkflowDocument(name: name));
  }

  Future<void> _publish() async {
    final controller = _controller;
    if (controller == null || _saving) return;
    setState(() => _saving = true);
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
    if (_loading) return const DVText('Loading workflows…');
    final controller = _controller;
    return DVBox.row(<Widget>[
      SizedBox(width: 220, child: _workflowList()),
      if (controller != null)
        Expanded(child: _builder(controller))
      else
        const Expanded(
          child: DVText('Select or create a workflow to edit.'),
        ),
    ]);
  }

  Widget _workflowList() {
    return DVBox.list(<Widget>[
      const DVText('Workflows')
          .modifier(const DVModifier().fontSize(20).fontWeight(FontWeight.bold)),
      if (_error != null) DVText('Could not read workflows: $_error'),
      for (final name in _names)
        GestureDetector(
          key: ValueKey<String>('dv-studio-workflow-$name'),
          onTap: () => _open(name),
          child: DVText(name),
        ),
      if (_names.isEmpty && _error == null)
        const DVText('No stored workflows yet.'),
      _DVStudioTextField(
        label: 'new workflow',
        value: _newName,
        onChanged: (String value) => _newName = value,
      ),
      GestureDetector(
        key: const ValueKey<String>('dv-studio-workflow-create'),
        onTap: _create,
        child: const DVText('Create workflow'),
      ),
    ]);
  }

  Widget _builder(DVWorkflowEditorController controller) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => DVBox.list(<Widget>[
        _toolbar(controller),
        if (_showingCode)
          DVText(controller.viewCode())
        else
          DVBox.row(<Widget>[
            Expanded(flex: 2, child: DVWorkflowPalette(items: widget.palette)),
            Expanded(flex: 5, child: DVWorkflowCanvas(controller: controller)),
            Expanded(
              flex: 3,
              child: DVWorkflowInspector(controller: controller),
            ),
          ]),
      ]),
    );
  }

  Widget _toolbar(DVWorkflowEditorController controller) {
    return DVBox.wrapLine(<Widget>[
      DVText(controller.document.name)
          .modifier(const DVModifier().fontSize(18).fontWeight(FontWeight.bold)),
      _action('Undo', controller.canUndo ? controller.undo : null,
          key: 'dv-studio-workflow-undo'),
      _action('Redo', controller.canRedo ? controller.redo : null,
          key: 'dv-studio-workflow-redo'),
      _action(_showingCode ? 'Design' : 'View code',
          () => setState(() => _showingCode = !_showingCode),
          key: 'dv-studio-workflow-view-code'),
      _action(_saving ? 'Publishing…' : 'Publish',
          _saving ? null : _publish,
          key: 'dv-studio-workflow-publish'),
      _action('Delete', _delete, key: 'dv-studio-workflow-delete'),
    ]);
  }
}

/// A toolbar action. A null [onTap] renders the label without making it
/// pressable, which is how an unavailable undo says so.
Widget _action(String label, VoidCallback? onTap,
    {required String key}) {
  return GestureDetector(
    key: ValueKey<String>(key),
    onTap: onTap,
    child: DVText(label),
  );
}

/// A plain text input for the Studio's own fields.
///
/// Private on purpose: the Studio must not add a primitive to the public
/// widget surface, and `DVForm` inputs are bound to model fields.
class _DVStudioTextField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _DVStudioTextField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_DVStudioTextField> createState() => _DVStudioTextFieldState();
}

class _DVStudioTextFieldState extends State<_DVStudioTextField> {
  late final TextEditingController _text =
      TextEditingController(text: widget.value);
  late final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DVBox.row(<Widget>[
      DVText(widget.label),
      Expanded(
        child: EditableText(
          controller: _text,
          focusNode: _focus,
          style: const TextStyle(fontSize: 14, color: Color(0xFF111111)),
          cursorColor: const Color(0xFF6C4BF4),
          backgroundCursorColor: const Color(0xFFCCCCCC),
          onChanged: widget.onChanged,
        ),
      ),
    ]);
  }
}
