import 'dart:async';

import 'package:flutter/material.dart' show Icon, IconData, Icons, Material;
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';
import 'studio_review.dart';

/// The Studio admin surface: a navigation rail, and the section it opens.
///
/// Pages is the builder: a site overview with a thumbnail of every stored
/// page, and — once a page is open — the editor, with the site's pages and an
/// insert panel or layer tree on the left, the page on an artboard in the
/// middle, and its properties on the right. Windows lists what the
/// application has open. Any other section is whatever the application
/// attaches; the Pro workflow builder is one.
class DVStudioScreen extends StatefulWidget {
  /// The store page documents are read from and published to.
  final DVPageStore store;

  /// Widget palette entries, defaulting to the Dartvel primitives.
  final List<DVStudioPaletteItem> palette;

  /// Sections beyond Pages, appended to the switcher in order.
  ///
  /// This is how the Pro workflow builder attaches: Studio does not know it
  /// exists, and a build without it has no Workflows tab rather than a tab
  /// that opens onto nothing.
  final List<DVStudioSection> sections;

  /// Attached to each editor the Pages tab opens, detached when it closes.
  /// The seam collaboration and permissions attach through.
  final List<DVStudioEditorHook> editorHooks;

  final DVStudioContent? content;
  final Object? actor;
  final List<String> reviewers;

  const DVStudioScreen({
    super.key,
    this.store = const DVPageStore(),
    this.palette = const <DVStudioPaletteItem>[],
    this.sections = const <DVStudioSection>[],
    this.editorHooks = const <DVStudioEditorHook>[],
    this.content,
    this.actor,
    this.reviewers = const <String>[],
  });

  @override
  State<DVStudioScreen> createState() => _DVStudioScreenState();
}

/// A section in Studio's switcher.
///
/// Studio ships Pages and Windows and takes the rest. That is not generality
/// for its own sake: the workflow builder is a Pro feature and lives in
/// dartvel_enterprise, while Studio itself is free and has to be complete
/// without it. A switcher that named its sections could not have one of them
/// removed, and a tab for a feature the build does not contain opens onto
/// nothing.
class DVStudioSection {
  /// Stable identifier, used for the tab's widget key.
  final String id;

  /// What the tab reads.
  final String label;

  /// The glyph on the navigation rail. Optional: a section without one gets a
  /// generic extension glyph rather than no way to be told apart.
  final IconData? icon;

  /// Builds the section body when its tab is selected.
  final Widget Function(BuildContext context) build;

  const DVStudioSection({
    required this.id,
    required this.label,
    required this.build,
    this.icon,
  });
}

class _DVStudioScreenState extends State<DVStudioScreen> {
  String _selected = 'pages';

  List<DVStudioSection> get _sections => <DVStudioSection>[
        DVStudioSection(
          id: 'pages',
          label: 'Pages',
          icon: DVStudioIcons.pages,
          build: (BuildContext context) => _DVStudioPagesSection(
            key: const ValueKey<String>('dv-studio-pages'),
            store: widget.store,
            palette: widget.palette,
            editorHooks: widget.editorHooks,
            content: widget.content,
            actor: widget.actor,
            reviewers: widget.reviewers,
            attached: <String>[
              for (final DVStudioSection section in widget.sections)
                section.label,
            ],
          ),
        ),
        // Every window the application has open, with a way to close one.
        // Free: what is open is not a Pro secret.
        DVStudioSection(
          id: 'windows',
          label: 'Windows',
          icon: DVStudioIcons.windows,
          build: (BuildContext context) => const _DVStudioWindowsSection(
            key: ValueKey<String>('dv-studio-windows'),
          ),
        ),
        ...widget.sections,
      ];

  @override
  Widget build(BuildContext context) {
    final List<DVStudioSection> sections = _sections;
    final DVStudioSection current = sections.firstWhere(
      (DVStudioSection section) => section.id == _selected,
      orElse: () => sections.first,
    );
    // A Material, not a coloured box: sections are free to use material
    // widgets, and a ColoredBox between a ListTile and its nearest Material
    // hides the tile's background and ink, which Flutter asserts on.
    return Material(
      color: DVStudioStyle.canvas,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _rail(sections),
          Expanded(
            // Keyed per section so switching away disposes the controller
            // rather than leaving an edit of one kind live under the other.
            child: KeyedSubtree(
              key: ValueKey<String>('dv-studio-body-${current.id}'),
              child: Builder(builder: current.build),
            ),
          ),
        ],
      ),
    );
  }

  /// The dark rail down the left: the product mark, then one item per
  /// section. Dark so the workspace beside it reads as the bright thing, the
  /// way every tool this has to stand beside does it.
  Widget _rail(List<DVStudioSection> sections) {
    return Container(
      width: 76,
      color: DVStudioStyle.rail,
      child: Column(
        children: <Widget>[
          const SizedBox(height: DVStudioStyle.space3),
          DVStudioStyle.tooltip(
            'Dartvel Studio',
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFF8B6DFF), DVStudioStyle.accent],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.diamond_outlined,
                  size: 19, color: Color(0xFFFFFFFF)),
            ),
          ),
          const SizedBox(height: DVStudioStyle.space4),
          Container(height: 1, width: 36, color: DVStudioStyle.railSelected),
          const SizedBox(height: DVStudioStyle.space2),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  for (final DVStudioSection section in sections)
                    _DVStudioRailItem(
                      section: section,
                      selected: section.id == _selected,
                      onTap: () => setState(() => _selected = section.id),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DVStudioRailItem extends StatefulWidget {
  final DVStudioSection section;
  final bool selected;
  final VoidCallback onTap;

  const _DVStudioRailItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_DVStudioRailItem> createState() => _DVStudioRailItemState();
}

class _DVStudioRailItemState extends State<_DVStudioRailItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool selected = widget.selected;
    final Color foreground =
        selected ? const Color(0xFFFFFFFF) : DVStudioStyle.railInk;
    return GestureDetector(
      key: ValueKey<String>('dv-studio-section-${widget.section.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Container(
          width: 64,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? DVStudioStyle.railSelected
                : _hover
                    ? const Color(0xFF1F1F29)
                    : const Color(0x00000000),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: <Widget>[
              Container(
                width: 32,
                height: 26,
                decoration: BoxDecoration(
                  color: selected
                      ? DVStudioStyle.accent
                      : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  widget.section.icon ?? DVStudioIcons.section,
                  size: 17,
                  color: foreground,
                ),
              ),
              const SizedBox(height: 5),
              // Scaled down rather than clipped: a section's name is how the
              // rail is read, and a longer one (or a larger system font) must
              // still fit the rail's width.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: DVText(widget.section.label).modifier(
                  const DVModifier()
                      .fontSize(10.5)
                      .color(foreground)
                      .fontWeight(
                          selected ? FontWeight.w600 : FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Which panel the editor's left column shows.
enum _DVStudioLeftPanel { insert, layers }

/// The artboard widths the device switcher offers.
enum _DVStudioDevice {
  desktop(1280, 'Desktop'),
  tablet(834, 'Tablet'),
  phone(390, 'Phone');

  const _DVStudioDevice(this.width, this.label);
  final double width;
  final String label;
}

/// Page management: an overview of the site, and the editor for one page.
class _DVStudioPagesSection extends StatefulWidget {
  final DVPageStore store;
  final List<DVStudioPaletteItem> palette;
  final List<DVStudioEditorHook> editorHooks;

  /// The labels of the sections attached beyond Pages and Windows, for the
  /// overview.
  final List<String> attached;

  final DVStudioContent? content;
  final Object? actor;
  final List<String> reviewers;

  const _DVStudioPagesSection({
    super.key,
    required this.store,
    required this.palette,
    required this.editorHooks,
    required this.attached,
    this.content,
    this.actor,
    this.reviewers = const <String>[],
  });

  @override
  State<_DVStudioPagesSection> createState() => _DVStudioPagesSectionState();
}

class _DVStudioPagesSectionState extends State<_DVStudioPagesSection> {
  List<String> _routes = <String>[];
  final Map<String, DVPageDocument> _documents = <String, DVPageDocument>{};

  /// Each route's versions, when the content workflow is attached, for the
  /// state badges on the page list and the cards.
  final Map<String, List<DVContentVersion<DVPageDocument>>> _versions =
      <String, List<DVContentVersion<DVPageDocument>>>{};

  /// The open page's workflow state and actions, when the workflow is
  /// attached.
  StudioReviewSession? _review;
  bool _reviewOpen = false;
  bool _historyOpen = false;
  bool _scheduling = false;
  DVStudioEditorController? _controller;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _showingCode = false;
  String _newRoute = '';
  DateTime? _lastPublished;
  _DVStudioLeftPanel _left = _DVStudioLeftPanel.insert;
  _DVStudioDevice _device = _DVStudioDevice.desktop;

  /// Null is "fit the artboard to the space available", which is what a
  /// 1280-wide page on a laptop needs and what nobody wants to work out.
  double? _zoom;

  /// Below this the side panels give the canvas back some of their width. At
  /// full width the editor needs about 1100 pixels before the artboard has
  /// room to be worth looking at, and a laptop split with a browser does not
  /// always have them.
  bool get _narrow =>
      (MediaQuery.maybeSizeOf(context)?.width ?? 1440) < 1100;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRoutes());
  }

  /// What each hook handed back for the current editor, called when it goes.
  List<VoidCallback> _detach = const <VoidCallback>[];

  @override
  void dispose() {
    _closeEditor();
    super.dispose();
  }

  @override
  void didUpdateWidget(_DVStudioPagesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final DVStudioContent? content = widget.content;
    // Compared by the id the workflow records rather than by identity, so an
    // application that builds a fresh user object on every frame does not
    // close the editor on every frame.
    final bool actorChanged = content != null &&
        oldWidget.content == content &&
        content.actorIdOf(oldWidget.actor) != content.actorIdOf(widget.actor);
    if (oldWidget.content != content || actorChanged) {
      // An editor opened for one person must not keep acting as them.
      setState(_closeEditor);
      unawaited(_loadRoutes());
    }
  }

  void _closeEditor() {
    for (final VoidCallback detach in _detach) {
      detach();
    }
    _detach = const <VoidCallback>[];
    _controller?.dispose();
    _controller = null;
    _review?.dispose();
    _review = null;
    _reviewOpen = false;
    _historyOpen = false;
    _scheduling = false;
  }

  Future<void> _loadRoutes() async {
    try {
      final DVStudioContent? content = widget.content;
      final List<String> stored = await widget.store.routes();
      // With the workflow attached the store holds only what is published,
      // so a page that has only been a draft is listed from its versions.
      final List<String> routes = content == null
          ? stored
          : (<String>{...stored, ...await content.routes()}.toList()..sort());
      final Map<String, List<DVContentVersion<DVPageDocument>>> versions =
          <String, List<DVContentVersion<DVPageDocument>>>{};
      if (content != null) {
        for (final String route in routes) {
          versions[route] = await content.workflow.versions(route);
        }
      }
      // The documents too, for the overview's thumbnails. A page that fails
      // to load is shown without one rather than taking the list down.
      final Map<String, DVPageDocument> documents = <String, DVPageDocument>{};
      for (final String route in routes) {
        try {
          final List<DVContentVersion<DVPageDocument>> of =
              versions[route] ?? const <DVContentVersion<DVPageDocument>>[];
          final DVPageDocument? document =
              studioOpenVersion(of)?.document ??
                  await widget.store.load(route) ??
                  studioPublishedVersion(of)?.document;
          if (document != null) documents[route] = document;
        } on Object {
          // Listed without a thumbnail.
        }
      }
      if (!mounted) return;
      setState(() {
        _routes = routes;
        _documents
          ..clear()
          ..addAll(documents);
        _versions
          ..clear()
          ..addAll(versions);
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
    final DVStudioContent? content = widget.content;
    if (content == null) {
      final DVPageDocument? document = await widget.store.load(route);
      if (!mounted || document == null) return;
      _select(document);
      return;
    }
    try {
      // The open version is what is being written; the published page is
      // what an edit starts from when nothing is open.
      final List<DVContentVersion<DVPageDocument>> versions =
          await content.workflow.versions(route);
      final DVPageDocument? document =
          studioOpenVersion(versions)?.document ??
              await widget.store.load(route) ??
              studioPublishedVersion(versions)?.document;
      if (!mounted || document == null) return;
      _select(document);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _select(DVPageDocument document, {bool keepPanels = false}) {
    final bool review = _reviewOpen;
    final bool history = _historyOpen;
    setState(() {
      _closeEditor();
      final DVStudioEditorController controller =
          DVStudioEditorController(document);
      _controller = controller;
      final DVStudioContent? content = widget.content;
      if (content != null) {
        // Before the hooks, so a hook can still take the publisher over.
        content.attach(controller, as: widget.actor);
        final StudioReviewSession session = StudioReviewSession(
          content: content,
          actor: widget.actor,
          route: document.route,
          onSettled: () => unawaited(_loadRoutes()),
        );
        _review = session;
        unawaited(session.reload());
        if (keepPanels) {
          _reviewOpen = review;
          _historyOpen = history;
          if (history) unawaited(session.loadHistory());
        }
      }
      _detach = <VoidCallback>[
        for (final DVStudioEditorHook hook in widget.editorHooks)
          hook(controller),
      ];
      _showingCode = false;
    });
  }

  void _create() {
    final String route = _newRoute.trim();
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
    final DVStudioEditorController? controller = _controller;
    if (controller == null || _saving) return;
    final StudioReviewSession? review = _review;
    if (review != null) {
      // Opens or edits a draft; the session shows a refusal where it happened.
      await review.saveDraft(controller);
      return;
    }
    setState(() => _saving = true);
    try {
      await controller.save();
      _lastPublished = DateTime.now();
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
    final DVStudioEditorController? controller = _controller;
    if (controller == null) return;
    final StudioReviewSession? review = _review;
    if (review != null) {
      // Through the workflow, never around it: withdrawing the open version
      // abandons the draft, and withdrawing the published one takes the
      // override down. Either way the refusal, if any, is shown.
      if (!await review.discard()) return;
      final DVPageDocument? standing =
          studioPublishedVersion(review.versions)?.document;
      if (!mounted) return;
      if (standing == null) {
        setState(_closeEditor);
      } else {
        _select(standing);
      }
      return;
    }
    await widget.store.delete(controller.document.route);
    if (!mounted) return;
    setState(_closeEditor);
    await _loadRoutes();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return DVStudioStyle.placeholder('Loading pages…');
    }
    final DVStudioEditorController? controller = _controller;
    if (controller == null) return _overview();
    final StudioReviewSession? review = _review;
    return ListenableBuilder(
      listenable: review == null
          ? controller
          : Listenable.merge(<Listenable>[controller, review]),
      builder: (BuildContext context, Widget? _) => _editor(controller),
    );
  }

  /// Restores a superseded version, then reopens the editor on it, so what
  /// is on the canvas is what is now published rather than an unsaved
  /// difference from it.
  Future<void> _restoreVersion(
      StudioReviewSession review, DVContentVersion<DVPageDocument> version) async {
    if (!await review.restore(version)) return;
    final DVPageDocument? standing =
        studioPublishedVersion(review.versions)?.document;
    if (!mounted || standing == null) return;
    _select(standing, keepPanels: true);
  }

  void _toggleReview() => setState(() {
        _reviewOpen = !_reviewOpen;
        if (_reviewOpen) {
          _historyOpen = false;
          _showingCode = false;
        }
      });

  void _toggleHistory() {
    setState(() {
      _historyOpen = !_historyOpen;
      if (_historyOpen) _showingCode = false;
    });
    if (_historyOpen) unawaited(_review?.loadHistory());
  }

  // --- overview -------------------------------------------------------------

  Widget _overview() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          width: 280,
          decoration: const BoxDecoration(
            color: DVStudioStyle.surface,
            border: Border(right: BorderSide(color: DVStudioStyle.line)),
          ),
          child: _pageList(),
        ),
        Expanded(child: _dashboard()),
      ],
    );
  }

  Widget _pageList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DVStudioStyle.panelHeader(
          title: 'Pages',
          subtitle: '${_routes.length}',
        ),
        // The new-page field comes first: it is the one thing on this panel
        // that starts work, and it is what the tests type into.
        Padding(
          padding: const EdgeInsets.all(DVStudioStyle.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DVStudioTextInput(
                value: _newRoute,
                placeholder: '/new-page',
                icon: DVStudioIcons.page,
                onChanged: (String value) => _newRoute = value,
                onSubmitted: (_) => _create(),
              ),
              const SizedBox(height: DVStudioStyle.space2),
              GestureDetector(
                key: const ValueKey<String>('dv-studio-create'),
                onTap: _create,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: DVStudioStyle.control(
                    'Create page',
                    enabled: true,
                    primary: true,
                    icon: DVStudioIcons.add,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(height: 1, color: DVStudioStyle.line),
        Padding(
          padding: const EdgeInsets.fromLTRB(DVStudioStyle.space4,
              DVStudioStyle.space4, DVStudioStyle.space4, DVStudioStyle.space2),
          child: DVStudioStyle.overline('Site'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: DVStudioStyle.space4, vertical: DVStudioStyle.space2),
            child: DVStudioStyle.caption('Could not read pages: $_error',
                color: DVStudioStyle.danger),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: DVStudioStyle.space4),
            children: <Widget>[
              ..._routeRows(withSubtitles: true),
              if (_routes.isEmpty && _error == null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: DVStudioStyle.space4,
                      vertical: DVStudioStyle.space2),
                  child: DVStudioStyle.caption('No stored pages yet.'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// One row per stored page, keyed by route. The overview and the editor
  /// both show these — one at a time — so a published page appears in the
  /// list the moment it is published, whichever view is open.
  List<Widget> _routeRows({required bool withSubtitles}) {
    final String? open = _controller?.document.route;
    return <Widget>[
      for (final String route in _routes)
        DVStudioListRow(
          key: ValueKey<String>('dv-studio-route-$route'),
          title: route,
          subtitle: withSubtitles ? _subtitleFor(route) : null,
          icon: route == '/' ? DVStudioIcons.home : DVStudioIcons.page,
          selected: route == open,
          trailing: widget.content == null
              ? DVStudioStyle.dot(DVStudioStyle.success)
              : _stateMarker(
                  route,
                  key: 'dv-studio-route-state-$route',
                  badge: withSubtitles,
                ),
          onTap: () => unawaited(_open(route)),
        ),
    ];
  }

  /// The version a page's badge describes: the one being written, else the
  /// one being served, else the last there was.
  DVContentVersion<DVPageDocument>? _stateVersion(String route) {
    final List<DVContentVersion<DVPageDocument>> versions =
        _versions[route] ?? const <DVContentVersion<DVPageDocument>>[];
    return studioOpenVersion(versions) ??
        studioPublishedVersion(versions) ??
        (versions.isEmpty ? null : versions.last);
  }

  /// A page's workflow state: a badge where there is room for the word, a
  /// dot with the word as its tooltip where there is not. A page stored
  /// before the workflow was attached is served, so it reads as published.
  Widget _stateMarker(String route,
      {required String key, required bool badge}) {
    final DVContentVersion<DVPageDocument>? version = _stateVersion(route);
    // An approval that no longer covers the content is not one: a badge
    // reading Approved over it is the quiet version of DV-CONTENT-002.
    final bool changed = version != null &&
        (version.state == DVContentState.approved ||
            version.state == DVContentState.scheduled) &&
        version.changedSinceApproval;
    final String label = version == null
        ? 'Published'
        : changed
            ? 'Changed'
            : studioContentStateLabel(version.state);
    final Color tone = version == null
        ? DVStudioStyle.success
        : changed
            ? DVStudioStyle.warning
            : studioContentStateTone(version.state);
    return KeyedSubtree(
      key: ValueKey<String>(key),
      child: badge
          ? DVStudioStyle.badge(label, tone: tone)
          : DVStudioStyle.tooltip(label, DVStudioStyle.dot(tone)),
    );
  }

  /// A page's title beside its route, when it has one of its own.
  String? _subtitleFor(String route) {
    final String? title = _documents[route]?.title;
    if (title == null || title.isEmpty || title == route) return null;
    return title;
  }

  Widget _dashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(DVStudioStyle.space8),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DVStudioStyle.title('Site overview'),
              const SizedBox(height: DVStudioStyle.space1),
              DVStudioStyle.body('Select or create a page to edit.',
                  color: DVStudioStyle.muted),
              const SizedBox(height: DVStudioStyle.space6),
              _stats(),
              const SizedBox(height: DVStudioStyle.space6),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) {
                  final bool wide = box.maxWidth >= 860;
                  final Widget pages = _pagesCard();
                  final Widget guide = _guideCard();
                  if (!wide) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        pages,
                        const SizedBox(height: DVStudioStyle.space4),
                        guide,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(flex: 7, child: pages),
                      const SizedBox(width: DVStudioStyle.space4),
                      Expanded(flex: 3, child: guide),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Four numbers, every one of them true: what the store holds, what the
  /// application has open, what is installed, and when this session last
  /// published. No invented traffic figures on a builder's front page.
  Widget _stats() {
    final List<Widget> cards = <Widget>[
      DVStudioStyle.statCard(
        label: 'Pages',
        value: '${_routes.length}',
        icon: DVStudioIcons.pages,
        detail: 'Stored in Studio',
      ),
      ValueListenableBuilder<List<DVWindow>>(
        valueListenable: DV.Platform.Window.all,
        builder: (BuildContext context, List<DVWindow> windows, Widget? _) =>
            DVStudioStyle.statCard(
          label: 'Open windows',
          value: '${windows.length}',
          icon: DVStudioIcons.windows,
          tone: const Color(0xFF0E8FC7),
          detail: windows.isEmpty ? 'None right now' : 'Live from the app',
        ),
      ),
      if (widget.content == null)
        DVStudioStyle.statCard(
          label: 'Sections',
          value: '${2 + widget.attached.length}',
          icon: DVStudioIcons.components,
          tone: const Color(0xFFB2479B),
          detail: widget.attached.isEmpty
              ? 'Pages and Windows'
              : 'Including ${widget.attached.join(', ')}',
        )
      else
        _needsReview(),
      if (widget.content == null)
        DVStudioStyle.statCard(
          label: 'Last publish',
          value: _lastPublished == null ? '—' : _ago(_lastPublished!),
          icon: DVStudioIcons.publish,
          tone: DVStudioStyle.success,
          detail: _lastPublished == null
              ? 'Nothing published this session'
              : 'This session',
        )
      else
        _lastWorkflowPublish(),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final int columns = box.maxWidth >= 900
            ? 4
            : box.maxWidth >= 520
                ? 2
                : 1;
        final double width =
            (box.maxWidth - DVStudioStyle.space4 * (columns - 1)) / columns;
        return Wrap(
          spacing: DVStudioStyle.space4,
          runSpacing: DVStudioStyle.space4,
          children: <Widget>[
            for (final Widget card in cards)
              SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }

  /// How many pages wait on a reviewer, and how many are scheduled: the two
  /// numbers somebody opening Studio in the morning needs first.
  Widget _needsReview() {
    int review = 0;
    int scheduled = 0;
    for (final String route in _routes) {
      switch (_stateVersion(route)?.state) {
        case DVContentState.review:
          review++;
        case DVContentState.scheduled:
          scheduled++;
        default:
          break;
      }
    }
    return KeyedSubtree(
      key: const ValueKey<String>('dv-studio-needs-review'),
      child: DVStudioStyle.statCard(
        label: 'Needs review',
        value: '$review',
        icon: DVStudioIcons.approvals,
        tone: DVStudioStyle.warning,
        detail: scheduled == 0
            ? (review == 0 ? 'Nothing waiting' : 'Waiting on a reviewer')
            : scheduled == 1
                ? 'And 1 page scheduled'
                : 'And $scheduled pages scheduled',
      ),
    );
  }

  /// The most recent publish the workflow recorded, not this session's: a
  /// publish somebody else made this morning is the one worth knowing about.
  Widget _lastWorkflowPublish() {
    DVContentVersion<DVPageDocument>? latest;
    for (final List<DVContentVersion<DVPageDocument>> versions
        in _versions.values) {
      for (final DVContentVersion<DVPageDocument> v in versions) {
        final DateTime? at = v.publishedAt;
        if (at != null &&
            (latest == null || at.isAfter(latest.publishedAt!))) {
          latest = v;
        }
      }
    }
    return DVStudioStyle.statCard(
      label: 'Last publish',
      value: latest == null ? '—' : _ago(latest.publishedAt!),
      icon: DVStudioIcons.publish,
      tone: DVStudioStyle.success,
      detail: latest == null
          ? 'Nothing published yet'
          : '${latest.documentId}${latest.publishedBy == null ? '' : ' by ${latest.publishedBy}'}',
    );
  }

  static String _ago(DateTime at) {
    final Duration since = DateTime.now().difference(at);
    if (since.inMinutes < 1) return 'Just now';
    if (since.inHours < 1) return '${since.inMinutes}m ago';
    return '${since.inHours}h ago';
  }

  Widget _pagesCard() {
    return DVStudioStyle.card(
      padding: const EdgeInsets.all(DVStudioStyle.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: DVStudioStyle.heading('All pages')),
              DVStudioStyle.badge(
                '${_routes.length} stored',
                tone: DVStudioStyle.muted,
              ),
            ],
          ),
          const SizedBox(height: DVStudioStyle.space4),
          if (_routes.isEmpty)
            SizedBox(
              height: 220,
              child: DVStudioStyle.emptyState(
                icon: DVStudioIcons.pages,
                title: 'Build your first page',
                message: 'Name a route in the panel on the left and press '
                    'Create page. It goes live the moment you publish.',
              ),
            )
          else
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                final int columns = box.maxWidth >= 640
                    ? 3
                    : box.maxWidth >= 400
                        ? 2
                        : 1;
                final double width =
                    (box.maxWidth - DVStudioStyle.space4 * (columns - 1)) /
                        columns;
                return Wrap(
                  spacing: DVStudioStyle.space4,
                  runSpacing: DVStudioStyle.space4,
                  children: <Widget>[
                    for (final String route in _routes)
                      SizedBox(
                        width: width,
                        child: _DVStudioPageCard(
                          route: route,
                          document: _documents[route],
                          onOpen: () => unawaited(_open(route)),
                          state: widget.content == null
                              ? null
                              : _stateMarker(
                                  route,
                                  key: 'dv-studio-card-state-$route',
                                  badge: true,
                                ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _guideCard() {
    Widget step(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: DVStudioStyle.space4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: DVStudioStyle.accentSoft,
                  borderRadius: BorderRadius.circular(DVStudioStyle.radius),
                ),
                child: Icon(icon, size: 16, color: DVStudioStyle.accent),
              ),
              const SizedBox(width: DVStudioStyle.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    DVText(title).modifier(const DVModifier()
                        .fontSize(13)
                        .color(DVStudioStyle.ink)
                        .fontWeight(FontWeight.w600)),
                    const SizedBox(height: 2),
                    DVStudioStyle.caption(body),
                  ],
                ),
              ),
            ],
          ),
        );
    return DVStudioStyle.card(
      padding: const EdgeInsets.all(DVStudioStyle.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DVStudioStyle.heading('How Studio works'),
          const SizedBox(height: DVStudioStyle.space4),
          step(DVStudioIcons.insert, 'Drag in elements',
              'Text, images, buttons and layouts, from the Insert panel.'),
          step(DVStudioIcons.design, 'Style what you select',
              'Every property the renderer honours is in the inspector.'),
          step(DVStudioIcons.publish, 'Publish to go live',
              'Stored pages take over their routes without a rebuild.'),
          step(DVStudioIcons.revert, 'Revert any time',
              'Deleting a stored page brings the compiled one back.'),
        ],
      ),
    );
  }

  // --- editor ---------------------------------------------------------------

  Widget _editor(DVStudioEditorController controller) {
    final bool narrow = _narrow;
    final StudioReviewSession? review = _review;
    final Widget editor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _toolbar(controller),
        if (review != null) ..._banners(review),
        Expanded(
          child: _showingCode
              ? _code(controller)
              : review != null && _historyOpen
                  ? StudioHistoryView(
                      session: review,
                      narrow: narrow,
                      onClose: _toggleHistory,
                      onRestore: (DVContentVersion<DVPageDocument> version) =>
                          unawaited(_restoreVersion(review, version)),
                    )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Container(
                      width: narrow ? 220 : 264,
                      decoration: const BoxDecoration(
                        color: DVStudioStyle.surface,
                        border: Border(
                            right: BorderSide(color: DVStudioStyle.line)),
                      ),
                      child: _leftColumn(controller),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints box) {
                          final double fit =
                              ((box.maxWidth - 96) / _device.width)
                                  .clamp(0.25, 1.0);
                          return DVStudioCanvas(
                            controller: controller,
                            viewportWidth: _device.width,
                            zoom: _zoom ?? fit,
                          );
                        },
                      ),
                    ),
                    Container(
                      width: review != null && _reviewOpen
                          ? (narrow ? 264 : 320)
                          : (narrow ? 248 : 300),
                      decoration: const BoxDecoration(
                        color: DVStudioStyle.surface,
                        border:
                            Border(left: BorderSide(color: DVStudioStyle.line)),
                      ),
                      child: review != null && _reviewOpen
                          ? StudioReviewPanel(
                              session: review,
                              controller: controller,
                              reviewers: widget.reviewers,
                              onClose: _toggleReview,
                              onSchedule: () =>
                                  setState(() => _scheduling = true),
                              onHistory: _toggleHistory,
                            )
                          : DVStudioInspector(controller: controller),
                    ),
                  ],
                ),
        ),
      ],
    );
    if (review == null || !_scheduling) return editor;
    return Stack(
      children: <Widget>[
        Positioned.fill(child: editor),
        Positioned.fill(
          child: StudioScheduleDialog(
            session: review,
            onClose: () {
              if (mounted) setState(() => _scheduling = false);
            },
          ),
        ),
      ],
    );
  }

  /// A refusal, and the warning that the open version changed after its
  /// approval, across the top of the editor where they cannot be missed. The
  /// warning moves into the review panel when that is open.
  List<Widget> _banners(StudioReviewSession review) {
    final StudioContentProblem? problem = review.problem;
    final DVContentVersion<DVPageDocument>? open = review.open;
    return <Widget>[
      if (problem != null)
        studioBanner(
          key: const ValueKey<String>('dv-studio-content-error'),
          tone: DVStudioStyle.danger,
          icon: Icons.error_outline,
          title: problem.title,
          detail: problem.detail,
          onDismiss: review.dismissProblem,
        ),
      if (open != null && open.changedSinceApproval && !_reviewOpen)
        studioBanner(
          key: const ValueKey<String>('dv-studio-content-changed'),
          tone: DVStudioStyle.warning,
          icon: Icons.warning_amber_rounded,
          title: 'Changed since approval',
          detail: studioChangedDetail(open),
          action: studioActionControl(
            'dv-studio-content-changed-review',
            'Open review',
            _toggleReview,
          ),
        ),
    ];
  }

  /// The site's pages, then the Insert panel or the layer tree.
  ///
  /// The pages stay in reach while a page is open, the way every site builder
  /// keeps them: switching page should not mean leaving the editor, and a
  /// page that has just been published should appear in the list at once.
  Widget _leftColumn(DVStudioEditorController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(DVStudioStyle.space4,
              DVStudioStyle.space3, DVStudioStyle.space4, DVStudioStyle.space1),
          child: DVStudioStyle.overline('Pages'),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 184),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: DVStudioStyle.space2),
            children: _routeRows(withSubtitles: false),
          ),
        ),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: DVStudioStyle.space3),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: DVStudioStyle.line),
              bottom: BorderSide(color: DVStudioStyle.line),
            ),
          ),
          alignment: Alignment.centerLeft,
          // Scaled down rather than overflowing: the panel narrows on a small
          // screen, and a label wider than it was measured for must not break
          // the layout.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: DVStudioSegmented<_DVStudioLeftPanel>(
              segments: const <DVStudioSegment<_DVStudioLeftPanel>>[
                DVStudioSegment<_DVStudioLeftPanel>(
                  value: _DVStudioLeftPanel.insert,
                  label: 'Insert',
                  icon: DVStudioIcons.insert,
                ),
                DVStudioSegment<_DVStudioLeftPanel>(
                  value: _DVStudioLeftPanel.layers,
                  label: 'Layers',
                  icon: DVStudioIcons.layers,
                ),
              ],
              value: _left,
              onChanged: (_DVStudioLeftPanel panel) =>
                  setState(() => _left = panel),
            ),
          ),
        ),
        Expanded(
          child: _left == _DVStudioLeftPanel.insert
              ? DVStudioPalette(items: widget.palette, controller: controller)
              : DVStudioLayers(controller: controller),
        ),
      ],
    );
  }

  Widget _toolbar(DVStudioEditorController controller) {
    final String route = controller.document.route;
    final bool stored = _routes.contains(route);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: DVStudioStyle.space3),
      decoration: const BoxDecoration(
        color: DVStudioStyle.surface,
        border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
      ),
      // Sized to what is there. Every control at once needs about 760 pixels,
      // and a laptop with Studio beside a browser's own panels does not have
      // them: the viewport controls go first, then the labels on Code and
      // Revert, and anything still too wide scales down rather than pushing
      // Publish off the end of the bar.
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final bool viewport = box.maxWidth >= 1000 && !_showingCode;
          final bool compact = box.maxWidth < 780;
          return Row(
            children: <Widget>[
              DVStudioIconButton(
                icon: Icons.arrow_back,
                tooltip: 'All pages',
                onTap: () => setState(_closeEditor),
              ),
              const SizedBox(width: DVStudioStyle.space2),
              Flexible(
                flex: 4,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      DVStudioStyle.heading(route),
                      const SizedBox(width: DVStudioStyle.space2),
                      if (_review != null)
                        studioStatePill(
                          _review!,
                          key: const ValueKey<String>(
                              'dv-studio-content-state'),
                          onTap: _toggleReview,
                        )
                      else if (stored)
                        DVStudioStyle.badge('Published',
                            tone: DVStudioStyle.success)
                      else
                        DVStudioStyle.badge('Draft',
                            tone: DVStudioStyle.warning),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (viewport) ...<Widget>[
                _viewportControls(),
                const Spacer(),
              ],
              Flexible(
                flex: 5,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: _actions(controller, compact: compact),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _viewportControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DVStudioSegmented<_DVStudioDevice>(
          segments: <DVStudioSegment<_DVStudioDevice>>[
            for (final _DVStudioDevice device in _DVStudioDevice.values)
              DVStudioSegment<_DVStudioDevice>(
                value: device,
                icon: switch (device) {
                  _DVStudioDevice.desktop => DVStudioIcons.desktop,
                  _DVStudioDevice.tablet => DVStudioIcons.tablet,
                  _DVStudioDevice.phone => DVStudioIcons.phone,
                },
                tooltip: '${device.label} · ${device.width.round()}',
              ),
          ],
          value: _device,
          onChanged: (_DVStudioDevice device) => setState(() {
            _device = device;
            _zoom = null;
          }),
        ),
        const SizedBox(width: DVStudioStyle.space2),
        DVStudioSegmented<double?>(
          segments: const <DVStudioSegment<double?>>[
            DVStudioSegment<double?>(value: null, label: 'Fit'),
            DVStudioSegment<double?>(value: 0.5, label: '50%'),
            DVStudioSegment<double?>(value: 1.0, label: '100%'),
          ],
          value: _zoom,
          onChanged: (double? zoom) => setState(() => _zoom = zoom),
        ),
      ],
    );
  }

  Widget _actions(DVStudioEditorController controller,
      {required bool compact}) {
    final VoidCallback toggleCode =
        () => setState(() => _showingCode = !_showingCode);
    final StudioReviewSession? review = _review;
    if (review != null) {
      return _contentActions(controller, review,
          compact: compact, toggleCode: toggleCode);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _keyedIcon('dv-studio-undo', DVStudioIcons.undo, 'Undo',
            controller.canUndo ? controller.undo : null),
        _keyedIcon('dv-studio-redo', DVStudioIcons.redo, 'Redo',
            controller.canRedo ? controller.redo : null),
        const SizedBox(width: DVStudioStyle.space2),
        Container(width: 1, height: 24, color: DVStudioStyle.line),
        const SizedBox(width: DVStudioStyle.space2),
        if (compact)
          _keyedIcon(
            'dv-studio-view-code',
            _showingCode ? DVStudioIcons.design : DVStudioIcons.code,
            _showingCode ? 'Design' : 'Code',
            toggleCode,
          )
        else
          _keyedControl(
            'dv-studio-view-code',
            _showingCode ? 'Design' : 'Code',
            toggleCode,
            icon: _showingCode ? DVStudioIcons.design : DVStudioIcons.code,
          ),
        const SizedBox(width: DVStudioStyle.space2),
        if (compact)
          _keyedIcon('dv-studio-revert', DVStudioIcons.revert, 'Revert', _revert)
        else
          _keyedControl('dv-studio-revert', 'Revert', _revert,
              icon: DVStudioIcons.revert),
        const SizedBox(width: DVStudioStyle.space2),
        _keyedControl(
          'dv-studio-publish',
          _saving ? 'Publishing…' : 'Publish',
          _saving ? null : _publish,
          icon: DVStudioIcons.publish,
          primary: true,
        ),
      ],
    );
  }

  /// The toolbar's actions with the content workflow attached: history and
  /// review beside undo and code, Save draft instead of a Publish that would
  /// not publish, Schedule when a version is ready for it, and one primary
  /// action that follows the version's state and the actor's policy.
  Widget _contentActions(
    DVStudioEditorController controller,
    StudioReviewSession review, {
    required bool compact,
    required VoidCallback toggleCode,
  }) {
    final DVContentVersion<DVPageDocument>? open = review.open;
    final StudioContentAction primary = review.primary(
      controller.document,
      openPanel: () => setState(() {
        _reviewOpen = true;
        _historyOpen = false;
        _showingCode = false;
      }),
      onSave: () => unawaited(_publish()),
    );
    final String? saveReason = review.saveReason(controller.document);
    final String? scheduleReason = review.scheduleReason();
    final bool schedulable = open != null &&
        (open.state == DVContentState.approved ||
            open.state == DVContentState.scheduled);
    final Widget divider = Padding(
      padding: const EdgeInsets.symmetric(horizontal: DVStudioStyle.space2),
      child: Container(width: 1, height: 24, color: DVStudioStyle.line),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _keyedIcon('dv-studio-undo', DVStudioIcons.undo, 'Undo',
            controller.canUndo ? controller.undo : null),
        _keyedIcon('dv-studio-redo', DVStudioIcons.redo, 'Redo',
            controller.canRedo ? controller.redo : null),
        divider,
        _keyedIcon(
          'dv-studio-view-code',
          _showingCode ? DVStudioIcons.design : DVStudioIcons.code,
          _showingCode ? 'Design' : 'Code',
          toggleCode,
        ),
        _keyedIcon('dv-studio-history', DVStudioIcons.history,
            _historyOpen ? 'Back to the canvas' : 'History', _toggleHistory),
        _keyedIcon('dv-studio-review', DVStudioIcons.approvals,
            _reviewOpen ? 'Close review' : 'Review', _toggleReview),
        if (review.versions.isNotEmpty)
          // Not the revert glyph: beside History's clock it read as a second
          // History, and this one withdraws a version.
          _keyedIcon(
            'dv-studio-revert',
            open != null ? DVStudioIcons.delete : Icons.unpublished_outlined,
            open != null ? 'Discard draft' : 'Unpublish',
            review.busy ? null : _revert,
          ),
        divider,
        if (open != null) ...<Widget>[
          if (compact)
            DVStudioStyle.tooltip(
              saveReason ?? 'Save draft',
              GestureDetector(
                key: const ValueKey<String>('dv-studio-save'),
                onTap: saveReason == null && !review.busy
                    ? () => unawaited(_publish())
                    : null,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(Icons.save_outlined,
                      size: 18,
                      color: saveReason == null
                          ? DVStudioStyle.ink
                          : DVStudioStyle.faint),
                ),
              ),
            )
          else
            studioActionControl(
              'dv-studio-save',
              'Save draft',
              saveReason == null && !review.busy
                  ? () => unawaited(_publish())
                  : null,
              icon: Icons.save_outlined,
              reason: saveReason,
            ),
          const SizedBox(width: DVStudioStyle.space2),
        ],
        if (schedulable) ...<Widget>[
          studioActionControl(
            'dv-studio-schedule',
            open.state == DVContentState.scheduled
                ? 'Reschedule…'
                : 'Schedule…',
            scheduleReason == null && !review.busy
                ? () => setState(() => _scheduling = true)
                : null,
            icon: Icons.schedule,
            reason: scheduleReason,
          ),
          const SizedBox(width: DVStudioStyle.space2),
        ],
        studioActionControl(
          'dv-studio-content-primary',
          primary.label,
          primary.run,
          icon: primary.icon,
          primary: true,
          reason: primary.reason,
        ),
      ],
    );
  }

  Widget _code(DVStudioEditorController controller) {
    return Container(
      color: const Color(0xFF12121C),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DVStudioStyle.space6),
        child: DVText(controller.document.toDartSource()).modifier(
          const DVModifier()
              .fontSize(13)
              .color(const Color(0xFFD9D6F2))
              .lineHeight(1.55),
        ),
      ),
    );
  }
}

/// A toolbar icon whose key sits on the GestureDetector itself, with a null
/// callback when there is nothing to do.
///
/// Not a [DVStudioIconButton]: tests — and anything else inspecting the tree —
/// ask the keyed widget whether it can be pressed, and an undo that says it
/// can when there is no history is the bug that asking catches.
Widget _keyedIcon(
    String key, IconData icon, String tooltip, VoidCallback? onTap) {
  return DVStudioStyle.tooltip(
    tooltip,
    GestureDetector(
      key: ValueKey<String>(key),
      onTap: onTap,
      child: MouseRegion(
        cursor:
            onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon,
              size: 18,
              color: onTap == null ? DVStudioStyle.faint : DVStudioStyle.ink),
        ),
      ),
    ),
  );
}

Widget _keyedControl(String key, String label, VoidCallback? onTap,
    {IconData? icon, bool primary = false}) {
  return GestureDetector(
    key: ValueKey<String>(key),
    onTap: onTap,
    child: MouseRegion(
      cursor:
          onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: DVStudioStyle.control(label,
          enabled: onTap != null, primary: primary, icon: icon),
    ),
  );
}

/// A page on the overview: a live thumbnail of the stored document, rendered
/// by the same renderer the running application uses, and its name.
class _DVStudioPageCard extends StatefulWidget {
  final String route;
  final DVPageDocument? document;
  final VoidCallback onOpen;

  /// The page's workflow state, when the content workflow is attached. A
  /// green dot otherwise, because without it every stored page is live.
  final Widget? state;

  const _DVStudioPageCard({
    required this.route,
    required this.document,
    required this.onOpen,
    this.state,
  });

  @override
  State<_DVStudioPageCard> createState() => _DVStudioPageCardState();
}

class _DVStudioPageCardState extends State<_DVStudioPageCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final DVPageDocument? document = widget.document;
    final String route = widget.route;
    // Not the route verbatim: the page list beside this already shows it, and
    // one piece of text should be one widget a reader — or a test — finds.
    final String name = document == null || document.title == route
        ? (route == '/' ? 'Home page' : route.substring(1))
        : document.title;
    return GestureDetector(
      onTap: widget.onOpen,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: DVStudioStyle.surface,
            border: Border.all(
                color: _hover ? DVStudioStyle.accent : DVStudioStyle.line),
            borderRadius: BorderRadius.circular(DVStudioStyle.radiusLarge),
            boxShadow: _hover ? DVStudioStyle.shadow : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(DVStudioStyle.radiusLarge - 1)),
                child: Container(
                  height: 150,
                  color: DVStudioStyle.canvas,
                  child: document == null
                      ? const Center(
                          child: Icon(DVStudioIcons.page,
                              size: 28, color: DVStudioStyle.faint),
                        )
                      : _thumbnail(document),
                ),
              ),
              Container(height: 1, color: DVStudioStyle.line),
              Padding(
                padding: const EdgeInsets.all(DVStudioStyle.space3),
                child: Row(
                  children: <Widget>[
                    Icon(route == '/' ? DVStudioIcons.home : DVStudioIcons.page,
                        size: 15, color: DVStudioStyle.muted),
                    const SizedBox(width: DVStudioStyle.space2),
                    Expanded(
                      child: DVText(name).modifier(const DVModifier()
                          .fontSize(13)
                          .color(DVStudioStyle.ink)
                          .fontWeight(FontWeight.w600)),
                    ),
                    widget.state ?? DVStudioStyle.dot(DVStudioStyle.success),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The page drawn at desktop width and scaled into the card, clipped to the
  /// top of it — what a person recognises a page by.
  static Widget _thumbnail(DVPageDocument document) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          const double pageWidth = 1280;
          final double scale = box.maxWidth / pageWidth;
          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: pageWidth,
              maxWidth: pageWidth,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topLeft,
                child: Container(
                  width: pageWidth,
                  color: const Color(0xFFFFFFFF),
                  child: DVPageDocumentRenderer(document),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The window inspector: the window manager's list, live, each with a close.
class _DVStudioWindowsSection extends StatelessWidget {
  const _DVStudioWindowsSection({super.key});

  static String _idOf(DVWindow w) => w.nativeId ?? w.route.path;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<DVWindow>>(
        valueListenable: DV.Platform.Window.all,
        builder: (BuildContext context, List<DVWindow> windows, Widget? _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DVStudioStyle.panelHeader(
                title: 'Windows',
                subtitle: '${windows.length} open',
              ),
              Expanded(
                child: windows.isEmpty
                    ? DVStudioStyle.emptyState(
                        icon: DVStudioIcons.windows,
                        title: 'No windows open.',
                        message: 'Windows, tabs and panels the application '
                            'opens appear here while they are open.',
                      )
                    : ListView(
                        padding: const EdgeInsets.all(DVStudioStyle.space6),
                        children: <Widget>[
                          for (final DVWindow w in windows)
                            Padding(
                              padding: const EdgeInsets.only(
                                  bottom: DVStudioStyle.space3),
                              child: KeyedSubtree(
                                key: ValueKey<String>(
                                    'dv-studio-window-${_idOf(w)}'),
                                child: _windowCard(w),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      );

  Widget _windowCard(DVWindow w) {
    return DVStudioStyle.card(
      padding: const EdgeInsets.all(DVStudioStyle.space4),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: DVStudioStyle.accentSoft,
              borderRadius: BorderRadius.circular(DVStudioStyle.radius),
            ),
            child: const Icon(DVStudioIcons.windows,
                size: 18, color: DVStudioStyle.accent),
          ),
          const SizedBox(width: DVStudioStyle.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DVStudioStyle.heading(w.route.path),
                if (w.nativeId != null)
                  DVStudioStyle.caption('Native id ${w.nativeId}',
                      color: DVStudioStyle.faint),
              ],
            ),
          ),
          // Scaled rather than overflowing when the window list is narrow:
          // the close button has to stay on screen.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DVStudioStyle.badge(w.kind.name),
                  const SizedBox(width: DVStudioStyle.space2),
                  DVStudioStyle.badge(w.presentation.name,
                      tone: DVStudioStyle.muted),
                  const SizedBox(width: DVStudioStyle.space4),
                  GestureDetector(
                    key: ValueKey<String>('dv-studio-window-close-${_idOf(w)}'),
                    onTap: () => unawaited(w.close()),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: DVStudioStyle.control(
                        'Close',
                        enabled: true,
                        icon: DVStudioIcons.close,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
