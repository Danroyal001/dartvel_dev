import 'dart:async';
import 'dart:math' as math;

// Not re-exported by the dartvel_flutter barrel, whose core exports are a
// `show` list.
import 'package:dartvel_core/dartvel.dart'
    show DVAlerting, DVFlags, DVHealthReport, DVIncidents;
import 'package:flutter/material.dart'
    show Icon, IconData, Icons, InkWell, Material, showGeneralDialog;
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';
import 'studio_command_palette.dart';
import 'studio_flags.dart';
import 'studio_formula.dart';
import 'studio_formula_bar.dart';
import 'studio_operations.dart';
import 'studio_review.dart';

/// The Studio admin surface: a navigation rail, and the section it opens.
///
/// Pages is the builder: a site overview with a thumbnail of every stored
/// page, and — once a page is open — the editor, with the site's pages and an
/// insert panel or layer tree on the left, the page on an artboard in the
/// middle, and its properties on the right. Any other section is whatever the application
/// attaches; the Pro workflow builder is one.
class DVStudioScreen extends StatefulWidget {
  /// The store page documents are read from and published to.
  final DVPageStore store;

  /// Where the site's routes come from: the application's compiled routes
  /// and the pages [store] holds, each marked for what it is. Without it
  /// Pages lists what [store] holds and nothing it did not publish.
  final DVStudioSiteSource? site;

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

  /// The flag runtime, which adds a Flags section: every declared flag, its
  /// rules, who gets what, rule edits applied to this running app, and a
  /// debug-build override. Without it there is no Flags tab.
  final DVFlags? flags;

  /// The alert rule engine, which adds an Operations section: service levels
  /// and their error budgets, rule state and delivery, and analysis findings.
  final DVAlerting? alerting;

  /// The incidents the Operations section lists and writes to, as [actor].
  /// Without this, the alerting runtime's own store is used; without either,
  /// there is no Operations tab.
  final DVIncidents? incidents;

  /// The clock the Operations section judges burn rates, ages and new
  /// timeline entries by.
  final DateTime Function()? clock;

  /// The health report the status page preview is built from. Defaults to
  /// running the application's registered health checks.
  final Future<DVHealthReport> Function()? statusHealth;

  const DVStudioScreen({
    super.key,
    this.store = const DVPageStore(),
    this.site,
    this.palette = const <DVStudioPaletteItem>[],
    this.sections = const <DVStudioSection>[],
    this.editorHooks = const <DVStudioEditorHook>[],
    this.content,
    this.actor,
    this.reviewers = const <String>[],
    this.flags,
    this.alerting,
    this.incidents,
    this.clock,
    this.statusHealth,
  });

  @override
  State<DVStudioScreen> createState() => _DVStudioScreenState();
}

/// A section in Studio's switcher.
///
/// Studio ships Pages and takes the rest. That is not generality
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
            site: widget.site,
            palette: widget.palette,
            editorHooks: widget.editorHooks,
            content: widget.content,
            actor: widget.actor,
            reviewers: widget.reviewers,
            attached: <String>[
              for (final DVStudioSection section in _attached) section.label,
            ],
          ),
        ),
        if (widget.flags case final DVFlags flags)
          DVStudioSection(
            id: 'flags',
            label: 'Flags',
            icon: DVStudioIcons.flags,
            build: (BuildContext context) => StudioFlagsSection(
              key: const ValueKey<String>('dv-studio-flags'),
              flags: flags,
            ),
          ),
        if (widget.alerting != null || widget.incidents != null)
          DVStudioSection(
            id: 'operations',
            label: 'Operations',
            icon: DVStudioIcons.operations,
            build: (BuildContext context) => StudioOperationsSection(
              key: const ValueKey<String>('dv-studio-operations'),
              alerting: widget.alerting,
              incidents: widget.incidents ?? widget.alerting?.incidents,
              actor: _operationsActor,
              now: widget.clock,
              health: widget.statusHealth,
            ),
          ),
        ..._attached,
      ];

  /// The attached sections, a later one with an id already used taking the
  /// earlier one's place: Studio Pro's Backend, with the builder, stands
  /// where free Studio's list of backend functions stood.
  List<DVStudioSection> get _attached {
    final Map<String, DVStudioSection> byId = <String, DVStudioSection>{};
    for (final DVStudioSection section in widget.sections) {
      byId[section.id] = section;
    }
    return byId.values.toList();
  }

  /// The name incident entries are written under: the actor itself when it
  /// is a string, or the id the content workflow records for it. Anything
  /// else writes nothing, rather than a timeline signed "Instance of User".
  String? get _operationsActor {
    final Object? actor = widget.actor;
    if (actor is String) return actor.isEmpty ? null : actor;
    if (actor == null) return null;
    return widget.content?.actorIdOf(actor);
  }

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
    // Keyed per section so switching away disposes the controller rather
    // than leaving an edit of one kind live under the other.
    final Widget body = Expanded(
      child: KeyedSubtree(
        key: ValueKey<String>('dv-studio-body-${current.id}'),
        child: Builder(builder: current.build),
      ),
    );
    // On a phone the rail's 76 points are a fifth of the screen, so the
    // sections move to a bar along the bottom, where a thumb reaches them.
    final bool phone =
        (MediaQuery.maybeSizeOf(context)?.width ?? 1440) < dvStudioPhoneWidth;
    // Ctrl+K (Cmd+K) over all of it. The sections are here; each section
    // adds what can be done inside it while it is on screen.
    return DVStudioCommandScope(
      child: Builder(builder: (BuildContext inner) {
        DVStudioCommandScope.provide(inner, this, () => <DVStudioCommand>[
              for (final DVStudioSection section in sections)
                DVStudioCommand(
                  id: 'go-${section.id}',
                  title: 'Go to ${section.label}',
                  group: 'Go to',
                  run: () => setState(() => _selected = section.id),
                ),
              DVStudioCommand(
                id: 'shortcuts',
                title: 'Keyboard shortcuts',
                group: 'Help',
                keywords: const <String>['keys', 'help'],
                run: () => unawaited(dvShowStudioShortcuts(inner)),
              ),
            ]);
        return _frame(sections, body, phone);
      }),
    );
  }

  Widget _frame(List<DVStudioSection> sections, Widget body, bool phone) {
    return Material(
      color: DVStudioStyle.canvas,
      child: phone
          ? Column(
              crossAxisAlignment: .stretch,
              children: <Widget>[body, _bottomBar(sections)],
            )
          : Row(
              crossAxisAlignment: .stretch,
              children: <Widget>[_rail(sections), body],
            ),
    );
  }

  /// The sections along the bottom of a phone, scrolling sideways when there
  /// are more than fit.
  Widget _bottomBar(List<DVStudioSection> sections) {
    final double inset = MediaQuery.maybePaddingOf(context)?.bottom ?? 0;
    return Container(
      key: const ValueKey<String>('dv-studio-bottom-bar'),
      color: DVStudioStyle.rail,
      padding: .only(bottom: inset),
      child: SingleChildScrollView(
        scrollDirection: .horizontal,
        child: Row(
          children: <Widget>[
            for (final DVStudioSection section in sections)
              SizedBox(
                width: 72,
                child: _DVStudioRailItem(
                  section: section,
                  selected: section.id == _selected,
                  onTap: () => setState(() => _selected = section.id),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The dark rail down the left: the product mark, then one item per
  /// section. Dark so the workspace beside it reads as the bright thing, the
  /// way every tool this has to stand beside does it.
  Widget _rail(List<DVStudioSection> sections) {
    return Container(
      key: const ValueKey<String>('dv-studio-rail'),
      width: 76,
      color: DVStudioStyle.rail,
      child: Column(
        children: <Widget>[
          const SizedBox(height: DVStudioStyle.space3),
          DVStudioStyle.tooltip(
            'Dartvel Studio',
            // On the rail itself. A white tile under it read as a logo
            // pasted onto a dark tool, and the mark's own gradient is
            // bright enough on the rail without one.
            Container(
              key: const ValueKey<String>('dv-studio-mark'),
              width: 32,
              height: 32,
              child: const CustomPaint(painter: DVStudioMarkPainter()),
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
      behavior: .opaque,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Container(
          width: 64,
          margin: const .symmetric(vertical: 2),
          padding: const .symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? DVStudioStyle.railSelected
                : _hover
                    ? const Color(0xFF1F1F29)
                    : const Color(0x00000000),
            borderRadius: .circular(10),
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
                  borderRadius: .circular(8),
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
                fit: .scaleDown,
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
  final DVStudioSiteSource? site;
  final List<DVStudioPaletteItem> palette;
  final List<DVStudioEditorHook> editorHooks;

  /// The labels of the sections attached beyond Pages, for the overview.
  final List<String> attached;

  final DVStudioContent? content;
  final Object? actor;
  final List<String> reviewers;

  const _DVStudioPagesSection({
    super.key,
    required this.store,
    this.site,
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
  /// The routes a stored document serves: published from Studio, over a
  /// compiled page or at a route of its own.
  List<String> _routes = <String>[];

  /// Every route the site answers, compiled and stored, each marked.
  List<DVStudioSitePage> _site = <DVStudioSitePage>[];

  /// The compiled page open in the editor, overridden or not, or null for a
  /// page only Studio serves.
  DVStudioSitePage? _compiled;

  /// The compiled page drawn as the application draws it, where Studio runs
  /// inside the application. Shown until an override of it is started.
  Widget? _live;
  final GlobalKey _liveKey = GlobalKey(debugLabel: 'dv-studio-live-page');

  /// Whether the open compiled page is being edited into an override.
  bool _overriding = false;

  /// The site's route list could not be read; the stored pages are shown.
  String? _siteError;

  DVStudioSitePage? _pageAt(String route) {
    for (final DVStudioSitePage page in _site) {
      if (page.path == route) return page;
    }
    return null;
  }
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

  /// Below this the editor shows one pane at a time.
  bool get _phone =>
      (MediaQuery.maybeSizeOf(context)?.width ?? 1440) < dvStudioPhoneWidth;

  /// Which pane a phone shows.
  _DVStudioPane _pane = _DVStudioPane.page;

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
      // Every route the site answers. A draft the workflow holds for a route
      // nothing serves yet is a Studio page all the same.
      List<DVStudioSitePage> site = <DVStudioSitePage>[];
      String? siteError;
      final DVStudioSiteSource? source = widget.site;
      if (source != null) {
        try {
          site = await source.pages();
        } catch (error) {
          siteError = '$error';
        }
      }
      final Set<String> listed = <String>{
        for (final DVStudioSitePage page in site) page.path,
      };
      site = <DVStudioSitePage>[
        ...site,
        for (final String route in routes)
          if (!listed.contains(route))
            DVStudioSitePage(
              path: route,
              kind: DVStudioPageKind.stored,
              title: documents[route]?.title,
            ),
      ]..sort((DVStudioSitePage a, DVStudioSitePage b) =>
          a.path.compareTo(b.path));
      if (!mounted) return;
      setState(() {
        _routes = routes;
        _site = site;
        _siteError = siteError;
        final DVStudioSitePage? compiled = _compiled;
        if (compiled != null) _compiled = _pageAt(compiled.path) ?? compiled;
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
    final DVStudioSitePage? page = _pageAt(route);
    if (page != null && page.kind == DVStudioPageKind.code) {
      await _openCompiled(page);
      return;
    }
    // A stored document over a compiled page is still that page's override:
    // the editor says so, and deleting it brings the compiled one back.
    final DVStudioSitePage? compiled =
        page != null && page.isCompiled ? page : null;
    final DVStudioContent? content = widget.content;
    if (content == null) {
      final DVPageDocument? document = await widget.store.load(route);
      if (!mounted || document == null) return;
      _select(document, compiled: compiled);
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
      _select(document, compiled: compiled);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  /// Opens a compiled page: its structure on the artboard, or the page
  /// itself where Studio runs inside the application, read-only until an
  /// override of it is started.
  Future<void> _openCompiled(DVStudioSitePage page) async {
    final DVStudioSiteSource? source = widget.site;
    final Widget? live =
        page.isDynamic ? null : source?.preview?.call(page.path);
    Object? tree;
    final Future<Object?> Function(String route)? structure =
        source?.structure;
    if (live == null && page.structure && structure != null) {
      try {
        tree = await structure(page.path);
      } catch (_) {
        // Opened without it: the banner says what the page is.
      }
    }
    if (!mounted) return;
    _select(
      dvStudioDocumentFromStructure(page.path, tree, title: page.title),
      compiled: page,
      live: live,
    );
    if (live != null) {
      // The page's structure, read off it once it has drawn, so Layers shows
      // what it is made of.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final DVPageDocument? captured = _captureLive(page);
        if (captured == null || _overriding) return;
        _select(captured, compiled: page, live: live, reload: false);
      });
    }
  }

  /// The compiled page on the artboard, as a page document, or null when it
  /// is not drawn.
  DVPageDocument? _captureLive(DVStudioSitePage page) {
    final BuildContext? context = _liveKey.currentContext;
    if (!mounted || context == null || _compiled?.path != page.path) {
      return null;
    }
    return dvStudioDocumentFromStructure(
      page.path,
      dvStudioStructureOf(context),
      title: page.title,
    );
  }

  /// Starts an override of the open compiled page: the page's structure,
  /// editable. It takes over the route when it is deployed.
  void _startOverride() {
    final DVStudioSitePage? page = _compiled;
    final DVStudioEditorController? controller = _controller;
    if (page == null || controller == null) return;
    final DVPageDocument document =
        _captureLive(page) ?? controller.document;
    _select(document, compiled: page, live: _live, overriding: true);
  }

  void _select(
    DVPageDocument document, {
    bool keepPanels = false,
    DVStudioSitePage? compiled,
    Widget? live,
    bool overriding = false,
    bool reload = true,
  }) {
    final bool review = _reviewOpen;
    final bool history = _historyOpen;
    // A compiled page nobody has overridden is looked at, not edited: an
    // edit starts an override, on purpose.
    final bool readOnly = compiled != null &&
        compiled.kind == DVStudioPageKind.code &&
        !overriding;
    setState(() {
      _closeEditor();
      _compiled = compiled;
      _live = live;
      _overriding = overriding;
      final DVStudioEditorController controller =
          DVStudioEditorController(document, readOnly: readOnly);
      _controller = controller;
      // Publish goes to the store this screen was given. Left to the
      // controller's default it went to DV.Database, so Studio served by a
      // web-server binary published nowhere the server could read.
      controller.publisher = widget.store.save;
      final DVStudioContent? content = widget.content;
      if (content != null && !readOnly) {
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
        // On a phone the palette covers the page; an element dropped from
        // it goes back to the page, where it can be seen.
        controller.edits.listen((DVStudioEdit edit) {
          if (edit.kind == 'insert' && _pane == _DVStudioPane.elements && mounted) {
            setState(() => _pane = _DVStudioPane.page);
          }
        }).cancel,
      ];
      _showingCode = false;
    });
    // What is stored may have changed since the overview read it: another
    // person publishing, or this Studio in another tab.
    if (reload) unawaited(_loadRoutes());
  }

  void _create() {
    final String route = _newRoute.trim();
    if (route.isEmpty) return;
    // Editing a route that already has a page would otherwise start from a
    // blank one and overwrite it on the first save.
    if (_routes.contains(route) || _pageAt(route) != null) {
      unawaited(_open(route));
      return;
    }
    _select(DVPageDocument(route: route, title: route));
  }

  Future<void> _publish() async {
    final DVStudioEditorController? controller = _controller;
    // A compiled page is deployed only once somebody has chosen to edit it.
    if (controller == null || _saving || controller.readOnly) return;
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
    final String route = controller.document.route;
    final DVStudioSitePage? compiled = _compiled;
    await widget.store.delete(route);
    if (!mounted) return;
    await _loadRoutes();
    if (!mounted) return;
    // An override deleted is the compiled page back, so that is what opens.
    final DVStudioSitePage? restored = compiled == null ? null : _pageAt(route);
    if (restored != null && restored.kind == DVStudioPageKind.code) {
      await _openCompiled(restored);
    } else {
      setState(_closeEditor);
    }
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
    if (_phone) {
      // The page list on top, where a new page is started, and the overview
      // under it: side by side they left the overview 34 points.
      return Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Container(
            height: 240,
            decoration: const BoxDecoration(
              color: DVStudioStyle.surface,
              border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
            ),
            child: _pageList(),
          ),
          Expanded(child: _dashboard()),
        ],
      );
    }
    return Row(
      crossAxisAlignment: .stretch,
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
      crossAxisAlignment: .stretch,
      children: <Widget>[
        DVStudioStyle.panelHeader(
          title: 'Pages',
          subtitle: '${_site.length}',
        ),
        // The new-page field comes first: it is the one thing on this panel
        // that starts work, and it is what the tests type into.
        Padding(
          padding: const .all(DVStudioStyle.space3),
          child: Column(
            crossAxisAlignment: .stretch,
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
          padding: const .fromLTRB(DVStudioStyle.space4,
              DVStudioStyle.space4, DVStudioStyle.space4, DVStudioStyle.space2),
          child: DVStudioStyle.overline('Site'),
        ),
        if (_error != null)
          Padding(
            padding: const .symmetric(
                horizontal: DVStudioStyle.space4, vertical: DVStudioStyle.space2),
            child: DVStudioStyle.caption('Could not read pages: $_error',
                color: DVStudioStyle.danger),
          ),
        if (_siteError != null)
          Padding(
            key: const ValueKey<String>('dv-studio-site-error'),
            padding: const .symmetric(
                horizontal: DVStudioStyle.space4, vertical: DVStudioStyle.space2),
            child: DVStudioStyle.caption(
                'Could not read the compiled pages, so only the pages '
                'stored in Studio are listed: $_siteError',
                color: DVStudioStyle.danger),
          ),
        Expanded(
          child: ListView(
            padding: const .only(bottom: DVStudioStyle.space4),
            children: <Widget>[
              ..._routeRows(withSubtitles: true),
              if (_site.isEmpty && _error == null)
                Padding(
                  padding: const .symmetric(
                      horizontal: DVStudioStyle.space4,
                      vertical: DVStudioStyle.space2),
                  child: DVStudioStyle.caption('No pages yet.'),
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
    // The page on the canvas is listed even before its first publish: a list
    // that leaves out the page being edited reads as if it were somewhere
    // else, and highlights nothing.
    final List<String> every = <String>[
      for (final DVStudioSitePage page in _site) page.path,
    ];
    final bool openUnsaved =
        open != null && open.isNotEmpty && !every.contains(open);
    final List<String> routes =
        openUnsaved ? (<String>[...every, open]..sort()) : every;
    return <Widget>[
      for (final String route in routes)
        DVStudioListRow(
          key: ValueKey<String>('dv-studio-route-$route'),
          title: route,
          subtitle: withSubtitles ? _subtitleFor(route) : null,
          icon: route == '/'
              ? DVStudioIcons.home
              : _pageAt(route)?.kind == DVStudioPageKind.code
                  ? DVStudioIcons.code
                  : DVStudioIcons.page,
          selected: route == open,
          trailing: _rowTrailing(
            route,
            unsaved: openUnsaved && route == open,
            withSubtitles: withSubtitles,
          ),
          onTap: () => unawaited(_open(route)),
        ),
    ];
  }

  /// What a page's row ends with: a ring for the page on the canvas that
  /// nothing serves yet; the kind of a compiled page, overridden or not; a
  /// stored page's workflow state, or the green dot of a page that is live.
  Widget _rowTrailing(
    String route, {
    required bool unsaved,
    required bool withSubtitles,
  }) {
    if (unsaved) {
      // A ring, not the green dot: nothing is published here yet.
      return Container(
        key: const ValueKey<String>('dv-studio-route-unsaved'),
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: DVStudioStyle.faint, width: 1.5),
        ),
      );
    }
    final DVStudioSitePage? page = _pageAt(route);
    if (page != null && page.isCompiled) {
      return KeyedSubtree(
        key: ValueKey<String>('dv-studio-route-kind-$route'),
        child: withSubtitles
            ? DVStudioStyle.badge(dvStudioPageKindLabel(page),
                tone: dvStudioPageKindTone(page))
            : DVStudioStyle.tooltip(dvStudioPageKindLabel(page),
                DVStudioStyle.dot(dvStudioPageKindTone(page))),
      );
    }
    return widget.content == null
        ? DVStudioStyle.dot(DVStudioStyle.success)
        : _stateMarker(
            route,
            key: 'dv-studio-route-state-$route',
            badge: withSubtitles,
          );
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

  /// A page's title beside its route, when it has one of its own; for a
  /// compiled page, the file it is written in, and the parameters a dynamic
  /// route takes.
  String? _subtitleFor(String route) {
    final DVStudioSitePage? page = _pageAt(route);
    final String? title = _documents[route]?.title ?? page?.title;
    final List<String> parts = <String>[
      if (title != null && title.isNotEmpty && title != route) title,
      if (page != null && page.isDynamic)
        'One page per ${page.params.join(', ')}',
      if (page != null &&
          page.kind == DVStudioPageKind.code &&
          page.source != null)
        _fileOf(page.source!),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// `lib/pages/docs/cli.dart:5` is `docs/cli.dart`: the part of a compiled
  /// page's location somebody recognises it by.
  static String _fileOf(String source) {
    final String file = source.replaceFirst(RegExp(r':\d+$'), '');
    return file.startsWith('lib/pages/')
        ? file.substring('lib/pages/'.length)
        : file;
  }

  Widget _dashboard() {
    return SingleChildScrollView(
      padding: .all(_phone ? DVStudioStyle.space4 : DVStudioStyle.space8),
      child: Align(
        alignment: .topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: .stretch,
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
                      crossAxisAlignment: .stretch,
                      children: <Widget>[
                        pages,
                        const SizedBox(height: DVStudioStyle.space4),
                        guide,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: .start,
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

  /// Three numbers, every one of them true: what the store holds, what is
  /// installed, and when this session last deployed. No invented traffic figures on a builder's front page.
  Widget _stats() {
    final List<Widget> cards = <Widget>[
      KeyedSubtree(
        key: const ValueKey<String>('dv-studio-stat-pages'),
        child: DVStudioStyle.statCard(
          label: 'Pages',
          value: '${_site.length}',
          icon: DVStudioIcons.pages,
          detail: _pagesDetail(),
        ),
      ),
      if (widget.content == null)
        DVStudioStyle.statCard(
          label: 'Sections',
          value: '${1 + widget.attached.length}',
          icon: DVStudioIcons.components,
          tone: const Color(0xFFB2479B),
          detail: widget.attached.isEmpty
              ? 'Pages'
              : 'Including ${widget.attached.join(', ')}',
        )
      else
        _needsReview(),
      if (widget.content == null)
        DVStudioStyle.statCard(
          label: 'Last deploy',
          value: _lastPublished == null ? '—' : _ago(_lastPublished!),
          icon: DVStudioIcons.publish,
          tone: DVStudioStyle.success,
          detail: _lastPublished == null
              ? 'Nothing deployed this session'
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

  /// What the site's pages are: how many are compiled, how many Studio
  /// serves on its own, and how many compiled ones Studio has overridden.
  String _pagesDetail() {
    int compiled = 0;
    int stored = 0;
    int overridden = 0;
    for (final DVStudioSitePage page in _site) {
      switch (page.kind) {
        case DVStudioPageKind.code:
          compiled++;
        case DVStudioPageKind.stored:
          stored++;
        case DVStudioPageKind.override:
          compiled++;
          overridden++;
      }
    }
    if (_site.isEmpty) return 'None yet';
    return <String>[
      if (compiled > 0) '$compiled in code',
      if (stored > 0) '$stored made in Studio',
      if (overridden > 0) '$overridden overridden',
    ].join(' · ');
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
      label: 'Last deploy',
      value: latest == null ? '—' : _ago(latest.publishedAt!),
      icon: DVStudioIcons.publish,
      tone: DVStudioStyle.success,
      detail: latest == null
          ? 'Nothing deployed yet'
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
      padding: const .all(DVStudioStyle.space5),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: DVStudioStyle.heading('All pages')),
              DVStudioStyle.badge(
                _site.length == 1 ? '1 page' : '${_site.length} pages',
                tone: DVStudioStyle.muted,
              ),
            ],
          ),
          const SizedBox(height: DVStudioStyle.space4),
          if (_site.isEmpty)
            // At least 220, not exactly: on a narrow phone the message wraps
            // to more lines than a fixed box holds.
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 220),
              child: DVStudioStyle.emptyState(
                icon: DVStudioIcons.pages,
                title: 'Build your first page',
                message: 'Name a route under Pages and press Create page. '
                    'It goes live the moment you deploy.',
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
                    for (final DVStudioSitePage page in _site)
                      SizedBox(
                        width: width,
                        child: _DVStudioPageCard(
                          route: page.path,
                          page: page,
                          document: _documents[page.path],
                          onOpen: () => unawaited(_open(page.path)),
                          state: page.isCompiled
                              ? DVStudioStyle.badge(
                                  dvStudioPageKindLabel(page),
                                  tone: dvStudioPageKindTone(page),
                                )
                              : widget.content == null
                                  ? null
                                  : _stateMarker(
                                      page.path,
                                      key: 'dv-studio-card-state-${page.path}',
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
          padding: const .only(bottom: DVStudioStyle.space4),
          child: Row(
            crossAxisAlignment: .start,
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: DVStudioStyle.accentSoft,
                  borderRadius: .circular(DVStudioStyle.radius),
                ),
                child: Icon(icon, size: 16, color: DVStudioStyle.accent),
              ),
              const SizedBox(width: DVStudioStyle.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    DVText(title).modifier(const DVModifier()
                        .fontSize(13)
                        .color(DVStudioStyle.ink)
                        .fontWeight(.w600)),
                    const SizedBox(height: 2),
                    DVStudioStyle.caption(body),
                  ],
                ),
              ),
            ],
          ),
        );
    return DVStudioStyle.card(
      padding: const .all(DVStudioStyle.space5),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          DVStudioStyle.heading('How Studio works'),
          const SizedBox(height: DVStudioStyle.space4),
          step(DVStudioIcons.insert, 'Drag in elements',
              'Text, images, buttons and layouts, from the Insert panel.'),
          step(DVStudioIcons.design, 'Style what you select',
              'Every property the renderer honours is in the inspector.'),
          step(DVStudioIcons.code, 'Edit any page',
              'Every page the app has is here. Editing one written in code '
                  'makes a Studio override of it.'),
          step(DVStudioIcons.publish, 'Deploy to go live',
              'Stored pages take over their routes without a rebuild.'),
          step(DVStudioIcons.revert, 'Revert any time',
              'Deleting an override brings the compiled page back.'),
        ],
      ),
    );
  }

  // --- editor ---------------------------------------------------------------

  /// What the command palette offers while a page is open: its pages, what
  /// can be done to the page and the selected element, every element by
  /// name, and every element that can be inserted.
  List<DVStudioCommand> _commands(DVStudioEditorController controller) {
    final DVPageDocument document = controller.document;
    final String? selected = controller.selectedId;
    final bool editable = !controller.readOnly;
    final List<DVPageNode> nodes = <DVPageNode>[];
    void walk(DVPageNode n) {
      nodes.add(n);
      n.children.forEach(walk);
    }

    walk(document.root);
    return <DVStudioCommand>[
      for (final DVStudioSitePage page in _site)
        if (page.path != document.route)
          DVStudioCommand(
            id: 'open-${page.path}',
            title: 'Open page ${page.path}',
            group: 'Page',
            run: () => unawaited(_open(page.path)),
          ),
      if (editable && controller.canUndo)
        DVStudioCommand(
            id: 'undo', title: 'Undo', group: 'Edit', shortcut: 'Ctrl+Z',
            run: controller.undo),
      if (editable && controller.canRedo)
        DVStudioCommand(
            id: 'redo', title: 'Redo', group: 'Edit', shortcut: 'Ctrl+Shift+Z',
            run: controller.redo),
      if (editable && selected != null && selected != document.root.id) ...<DVStudioCommand>[
        DVStudioCommand(
            id: 'duplicate', title: 'Duplicate element', group: 'Element',
            shortcut: 'Ctrl+D', run: () => controller.duplicate(selected)),
        DVStudioCommand(
            id: 'delete', title: 'Delete element', group: 'Element',
            shortcut: 'Delete', run: () => controller.remove(selected)),
      ],
      DVStudioCommand(
        id: 'code',
        title: _showingCode ? 'Hide the code' : 'Show the code',
        group: 'Page',
        keywords: const <String>['source', 'export', 'dart'],
        run: () => setState(() => _showingCode = !_showingCode),
      ),
      for (final DVPageNode node in nodes)
        if (node.id != document.root.id)
          DVStudioCommand(
            id: 'select-${node.id}',
            title: 'Select ${dvStudioNodeTitle(node, document)}',
            group: 'Element',
            run: () => controller.select(node.id),
          ),
      if (editable)
        for (final DVStudioPaletteItem item in widget.palette.isEmpty
            ? DVStudioPaletteItem.defaults
            : widget.palette)
          DVStudioCommand(
            id: 'insert-${item.label}',
            title: 'Insert ${item.label}',
            group: 'Insert',
            run: () => controller.insert(item.create(),
                parent: dvStudioInsertTarget(controller)),
          ),
    ];
  }

  Widget _editor(DVStudioEditorController controller) {
    DVStudioCommandScope.provide(context, this, () => _commands(controller));
    final bool narrow = _narrow;
    final StudioReviewSession? review = _review;
    final Widget editor = Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        _toolbar(controller),
        // The selected element's fields as formulas, Excel's way: pick a
        // field, type, Enter. It writes through the same controller as the
        // canvas and the inspector, so it is one history and one document.
        if (!_showingCode)
          DVStudioFormulaBar(
            controller: controller,
            vocabulary: DVFormulaVocabulary(routes: <String>[
              for (final DVStudioSitePage page in _site)
                if (!page.isDynamic) page.path,
            ]),
          ),
        ?_compiledBanner(controller),
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
              : _workspace(controller, review, narrow),
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

  /// The editor's panes: Elements (insert and layers), the page, and Style
  /// (the inspector, or the review panel when that is open).
  ///
  /// Side by side where there is room. On a phone the three would need 564
  /// points before the page got any, so one shows at a time, chosen from a
  /// bar along the bottom, the page first.
  Widget _workspace(DVStudioEditorController controller,
      StudioReviewSession? review, bool narrow) {
    final Widget elements = _leftColumn(controller);
    final Widget page = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double fit =
            ((box.maxWidth - (_phone ? 24 : 96)) / _device.width)
                .clamp(0.25, 1.0);
        final Widget? live = _live;
        if (live != null && !_overriding) {
          return DVStudioLivePage(
            page: live,
            width: _device.width,
            zoom: _zoom,
            captureKey: _liveKey,
          );
        }
        return DVStudioCanvas(
          controller: controller,
          viewportWidth: _device.width,
          zoom: _zoom ?? fit,
        );
      },
    );
    final Widget style = review != null && _reviewOpen
        ? StudioReviewPanel(
            session: review,
            controller: controller,
            reviewers: widget.reviewers,
            onClose: _toggleReview,
            onSchedule: () => setState(() => _scheduling = true),
            onHistory: _toggleHistory,
          )
        : DVStudioInspector(controller: controller);
    if (_phone) {
      return Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Expanded(
            child: ColoredBox(
              color: _pane == _DVStudioPane.page
                  ? DVStudioStyle.canvas
                  : DVStudioStyle.surface,
              child: switch (_pane) {
                _DVStudioPane.elements => elements,
                _DVStudioPane.page => page,
                _DVStudioPane.style => style,
              },
            ),
          ),
          _paneBar(),
        ],
      );
    }
    return Row(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Container(
          width: narrow ? 220 : 264,
          decoration: const BoxDecoration(
            color: DVStudioStyle.surface,
            border: Border(right: BorderSide(color: DVStudioStyle.line)),
          ),
          child: elements,
        ),
        Expanded(child: page),
        Container(
          width: review != null && _reviewOpen
              ? (narrow ? 264 : 320)
              : (narrow ? 248 : 300),
          decoration: const BoxDecoration(
            color: DVStudioStyle.surface,
            border: Border(left: BorderSide(color: DVStudioStyle.line)),
          ),
          child: style,
        ),
      ],
    );
  }

  /// The phone editor's pane switcher.
  Widget _paneBar() {
    Widget item(_DVStudioPane pane, IconData icon, String label) {
      final bool on = _pane == pane;
      return Expanded(
        child: GestureDetector(
          key: ValueKey<String>('dv-studio-pane-${pane.name}'),
          behavior: .opaque,
          onTap: () => setState(() => _pane = pane),
          child: Padding(
            padding: const .symmetric(vertical: 8),
            child: Column(
              mainAxisSize: .min,
              children: <Widget>[
                Icon(icon,
                    size: 20,
                    color: on ? DVStudioStyle.accent : DVStudioStyle.muted),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                        color: on ? DVStudioStyle.accent : DVStudioStyle.muted)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: DVStudioStyle.surface,
        border: Border(top: BorderSide(color: DVStudioStyle.line)),
      ),
      child: Row(children: <Widget>[
        item(_DVStudioPane.elements, DVStudioIcons.insert, 'Elements'),
        item(_DVStudioPane.page, DVStudioIcons.page, 'Page'),
        item(_DVStudioPane.style, DVStudioIcons.design, 'Style'),
      ]),
    );
  }

  /// What the open compiled page is, and the one thing to do with it: start
  /// an override, or delete the override to bring the compiled page back.
  Widget? _compiledBanner(DVStudioEditorController controller) {
    final DVStudioSitePage? page = _compiled;
    if (page == null) return null;
    final String where = page.source == null ? 'code' : _fileOf(page.source!);
    if (page.kind == DVStudioPageKind.code && !_overriding) {
      if (page.isDynamic) {
        return studioBanner(
          key: const ValueKey<String>('dv-studio-compiled-banner'),
          tone: DVStudioStyle.muted,
          icon: DVStudioIcons.code,
          title: 'A page for every ${page.params.join(', ')}',
          detail: '${page.path} is written in $where and draws a different '
              'page for each ${page.params.join(', ')}. Edit it there, or '
              'make a page at one address from Studio.',
        );
      }
      return studioBanner(
        key: const ValueKey<String>('dv-studio-compiled-banner'),
        tone: DVStudioStyle.accent,
        icon: DVStudioIcons.code,
        title: 'Written in code',
        detail: _live != null
            ? '${page.path} comes from $where, drawn here as the app draws '
                'it. Editing it makes a Studio copy that takes over '
                '${page.path} when you deploy it.'
            : '${page.path} comes from $where. This is its structure. '
                'Editing it makes a Studio copy that takes over ${page.path} '
                'when you deploy it.',
        action: studioActionControl(
          'dv-studio-override',
          'Edit this page',
          _startOverride,
          icon: DVStudioIcons.design,
          primary: true,
        ),
      );
    }
    final bool deployed = page.kind == DVStudioPageKind.override;
    return studioBanner(
      key: const ValueKey<String>('dv-studio-compiled-banner'),
      tone: DVStudioStyle.warning,
      icon: DVStudioIcons.revert,
      title: deployed ? 'Studio is serving this page' : 'Editing a copy',
      detail: deployed
          ? 'Studio\'s version of ${page.path} is live in place of the one '
              'in $where. Restore it to serve the compiled page again.'
          : 'Nothing changes on ${page.path} until you deploy. Deploying '
              'puts this in place of the page in $where.',
      action: deployed
          ? studioActionControl(
              'dv-studio-restore-compiled',
              'Restore compiled page',
              () => unawaited(_revert()),
              icon: DVStudioIcons.revert,
            )
          : null,
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
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Padding(
          padding: const .fromLTRB(DVStudioStyle.space4,
              DVStudioStyle.space3, DVStudioStyle.space4, DVStudioStyle.space1),
          child: DVStudioStyle.overline('Pages'),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 184),
          child: ListView(
            shrinkWrap: true,
            padding: const .only(bottom: DVStudioStyle.space2),
            children: _routeRows(withSubtitles: false),
          ),
        ),
        Container(
          height: 48,
          padding: const .symmetric(horizontal: DVStudioStyle.space3),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: DVStudioStyle.line),
              bottom: BorderSide(color: DVStudioStyle.line),
            ),
          ),
          alignment: .centerLeft,
          // Scaled down rather than overflowing: the panel narrows on a small
          // screen, and a label wider than it was measured for must not break
          // the layout.
          child: FittedBox(
            fit: .scaleDown,
            alignment: .centerLeft,
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
      padding: const .symmetric(horizontal: DVStudioStyle.space3),
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
                  fit: .scaleDown,
                  alignment: .centerLeft,
                  child: Row(
                    mainAxisSize: .min,
                    children: <Widget>[
                      DVStudioStyle.heading(route),
                      const SizedBox(width: DVStudioStyle.space2),
                      if (_compiled case final DVStudioSitePage page)
                        KeyedSubtree(
                          key: const ValueKey<String>('dv-studio-page-kind'),
                          child: _overriding || page.kind != DVStudioPageKind.code
                              ? DVStudioStyle.badge('Override',
                                  tone: DVStudioStyle.warning)
                              : DVStudioStyle.badge('Code',
                                  tone: DVStudioStyle.muted),
                        )
                      else if (_review != null)
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
                  fit: .scaleDown,
                  alignment: .centerRight,
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
      mainAxisSize: .min,
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
      mainAxisSize: .min,
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
        // Deploy, the word dartvel deploy uses, so the person who never opens
        // a terminal and the one who does say the same thing. Its menu holds
        // the other ways out, worded for someone who does not know what a
        // compiled page is.
        _keyedControl(
          'dv-studio-publish',
          _saving ? 'Deploying…' : 'Deploy',
          _saving || controller.readOnly ? null : _publish,
          icon: DVStudioIcons.publish,
          primary: true,
        ),
        const SizedBox(width: 4),
        _DVStudioDeployMenu(
          document: _controller?.document,
          onDeploy: _saving ? null : () => unawaited(_publish()),
          onRestore: () => unawaited(_revert()),
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
      padding: const .symmetric(horizontal: DVStudioStyle.space2),
      child: Container(width: 1, height: 24, color: DVStudioStyle.line),
    );
    return Row(
      mainAxisSize: .min,
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
        padding: const .all(DVStudioStyle.space6),
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

/// The menu beside Deploy: where the page goes, deploy now, or put the page
/// from the last build back. Each option says what a visitor will see, not
/// what the store does.
///
/// The targets are ticked on the page itself, so the next Deploy, from the
/// menu or the button beside it, goes to the same places.
class _DVStudioDeployMenu extends StatelessWidget {
  const _DVStudioDeployMenu({
    required this.document,
    required this.onDeploy,
    required this.onRestore,
  });

  final DVPageDocument? document;
  final VoidCallback? onDeploy;
  final VoidCallback onRestore;

  static String _detail(DVDeployTarget target) => switch (target) {
        DVDeployTarget.web => 'Live the moment you deploy.',
        DVDeployTarget.extensions => 'Next time the extension opens.',
        _ => 'Apps get it the next time they open.',
      };

  Future<void> _open(BuildContext context) async {
    final RenderObject? box = context.findRenderObject();
    final RenderObject? overlay =
        Overlay.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox || overlay is! RenderBox) return;
    final Offset origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    const double width = 320;
    final double left = (origin.dx + box.size.width - width)
        .clamp(8, math.max(8, overlay.size.width - width - 8))
        .toDouble();
    final String? picked = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: const Color(0x00000000),
      transitionDuration: .zero,
      pageBuilder: (BuildContext dialog, _, __) => Stack(
        children: <Widget>[
          Positioned(
            left: left,
            top: origin.dy + box.size.height + 4,
            width: width,
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setMenu) {
                final DVPageDocument? page = document;
                final Set<DVDeployTarget> ticked =
                    page?.targets ?? DVDeployTarget.values.toSet();
                void toggle(DVDeployTarget target) {
                  if (page == null) return;
                  final Set<DVDeployTarget> next = <DVDeployTarget>{...ticked};
                  if (!next.remove(target)) next.add(target);
                  // Everything ticked is stored as everywhere, so a target
                  // added later reaches a page deployed to all of them.
                  setMenu(() => page.targets =
                      next.length == DVDeployTarget.values.length ? null : next);
                }

                final int count = ticked.length;
                return Material(
                  color: DVStudioStyle.surface,
                  elevation: 8,
                  borderRadius: .circular(DVStudioStyle.radius),
                  clipBehavior: .antiAlias,
                  // Every platform is listed, which is taller than a laptop
                  // screen below the toolbar; the menu scrolls instead.
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.max(160,
                          overlay.size.height - origin.dy - box.size.height - 16),
                    ),
                    child: Padding(
                    padding: const .symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: .min,
                      crossAxisAlignment: .stretch,
                      children: <Widget>[
                        Padding(
                          padding: const .fromLTRB(16, 4, 16, 4),
                          child: DVStudioStyle.overline('Deploy to'),
                        ),
                        // Only the targets scroll: Deploy now stays in reach.
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: .stretch,
                              children: <Widget>[
                        for (final DVDeployTarget target
                            in DVDeployTarget.values)
                          InkWell(
                            key: ValueKey<String>(
                                'dv-studio-deploy-target-${target.name}'),
                            onTap: () => toggle(target),
                            child: Padding(
                              padding: const .symmetric(
                                  horizontal: 12, vertical: 6),
                              child: Row(
                                crossAxisAlignment: .start,
                                children: <Widget>[
                                  Icon(
                                    ticked.contains(target)
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank,
                                    size: 20,
                                    color: ticked.contains(target)
                                        ? DVStudioStyle.accent
                                        : DVStudioStyle.muted,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(target.label,
                                            style: const TextStyle(
                                                fontSize: 14,
                                                color: DVStudioStyle.ink)),
                                        Text(_detail(target),
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: DVStudioStyle.muted)),
                                        for (final DVDeployPlatform platform
                                            in DVDeployPlatform.of(target))
                                          _DVStudioDeployPlatformLine(
                                              platform: platform),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const .symmetric(horizontal: 12),
                          child: _keyedControl(
                            'dv-studio-deploy-now',
                            'Deploy now',
                            onDeploy == null || count == 0
                                ? null
                                : () => Navigator.of(dialog).pop('deploy'),
                            icon: DVStudioIcons.publish,
                            primary: true,
                          ),
                        ),
                        Padding(
                          padding: const .fromLTRB(16, 4, 16, 6),
                          child: Text(
                            count == DVDeployTarget.values.length
                                ? 'To every target'
                                : count == 0
                                    ? 'Tick at least one target'
                                    : 'To $count target${count == 1 ? '' : 's'}',
                            style: const TextStyle(
                                fontSize: 12, color: DVStudioStyle.muted),
                          ),
                        ),
                        Container(height: 1, color: DVStudioStyle.line),
                        InkWell(
                          key: const ValueKey<String>('dv-studio-revert'),
                          onTap: () => Navigator.of(dialog).pop('restore'),
                          child: const Padding(
                            padding: .fromLTRB(16, 10, 16, 6),
                            child: Column(
                              crossAxisAlignment: .start,
                              children: <Widget>[
                                Text('Restore original page',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: .w600,
                                        color: DVStudioStyle.ink)),
                                Text(
                                    'Brings back the page from your last build.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: DVStudioStyle.muted)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
    switch (picked) {
      case 'deploy':
        onDeploy?.call();
      case 'restore':
        onRestore();
    }
  }

  @override
  Widget build(BuildContext context) => _keyedIcon(
        'dv-studio-deploy-menu',
        Icons.expand_more,
        'More ways to deploy',
        () => unawaited(_open(context)),
      );
}

/// One platform under a Deploy group: its name, where it stands, and why
/// when it is not ready.
class _DVStudioDeployPlatformLine extends StatelessWidget {
  const _DVStudioDeployPlatformLine({required this.platform});

  final DVDeployPlatform platform;

  @override
  Widget build(BuildContext context) {
    final Color tone = switch (platform.status) {
      DVDeployStatus.ready => DVStudioStyle.success,
      DVDeployStatus.limited => DVStudioStyle.warning,
      DVDeployStatus.notYet => DVStudioStyle.faint,
    };
    return Padding(
      padding: const .only(top: 4),
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: Text(platform.label,
                    style:
                        const TextStyle(fontSize: 12, color: DVStudioStyle.ink)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const .symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: tone),
                  borderRadius: .circular(4),
                ),
                child: Text(platform.status.label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: .w600,
                        color: tone)),
              ),
            ],
          ),
          if (platform.reason.isNotEmpty)
            Text(platform.reason,
                style:
                    const TextStyle(fontSize: 11, color: DVStudioStyle.muted)),
        ],
      ),
    );
  }
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

  /// What the route is: compiled, stored, or a stored override.
  final DVStudioSitePage? page;
  final DVPageDocument? document;
  final VoidCallback onOpen;

  /// The page's workflow state, when the content workflow is attached. A
  /// green dot otherwise, because without it every stored page is live.
  final Widget? state;

  const _DVStudioPageCard({
    required this.route,
    this.page,
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
    final DVStudioSitePage? page = widget.page;
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
            borderRadius: .circular(DVStudioStyle.radiusLarge),
            boxShadow: _hover ? DVStudioStyle.shadow : null,
          ),
          child: Column(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              ClipRRect(
                borderRadius: const .vertical(
                    top: Radius.circular(DVStudioStyle.radiusLarge - 1)),
                child: Container(
                  key: ValueKey<String>('dv-studio-thumbnail-$route'),
                  height: 150,
                  color: DVStudioStyle.canvas,
                  child: document == null
                      ? _compiledFace(page)
                      : _thumbnail(document),
                ),
              ),
              Container(height: 1, color: DVStudioStyle.line),
              Padding(
                padding: const .all(DVStudioStyle.space3),
                child: Row(
                  children: <Widget>[
                    Icon(route == '/' ? DVStudioIcons.home : DVStudioIcons.page,
                        size: 15, color: DVStudioStyle.muted),
                    const SizedBox(width: DVStudioStyle.space2),
                    Expanded(
                      child: DVText(name).modifier(const DVModifier()
                          .fontSize(13)
                          .color(DVStudioStyle.ink)
                          .fontWeight(.w600)),
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

  /// A compiled page's face on its card: nothing Studio stores draws it, so
  /// the card says where it is written and what a dynamic route takes.
  static Widget _compiledFace(DVStudioSitePage? page) {
    final String? source = page?.source;
    return Center(
      child: Padding(
        padding: const .all(DVStudioStyle.space3),
        child: Column(
          mainAxisSize: .min,
          children: <Widget>[
            Icon(
              page != null && page.isCompiled
                  ? DVStudioIcons.code
                  : DVStudioIcons.page,
              size: 28,
              color: DVStudioStyle.faint,
            ),
            if (source != null) ...<Widget>[
              const SizedBox(height: DVStudioStyle.space2),
              DVStudioStyle.caption(
                source.replaceFirst(RegExp(r':\d+$'), ''),
                color: DVStudioStyle.muted,
              ),
            ],
            if (page != null && page.isDynamic) ...<Widget>[
              const SizedBox(height: DVStudioStyle.space1),
              DVStudioStyle.caption(
                'One page per ${page.params.join(', ')}',
                color: DVStudioStyle.faint,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The page drawn at a fixed scale into the card, clipped to the top of it
  /// -- what a person recognises a page by.
  ///
  /// At a fixed scale rather than fitted from desktop width: a 1280-pixel
  /// page shrunk into a card this size drew its text two pixels tall, which
  /// is an empty box. The sheet is at least the card's height, so the page's
  /// own colour fills it however little is on the page.
  static Widget _thumbnail(DVPageDocument document) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          const double scale = 0.42;
          final double pageWidth = box.maxWidth / scale;
          final double pageHeight =
              (box.maxHeight.isFinite ? box.maxHeight : 150) / scale;
          return ClipRect(
            child: OverflowBox(
              alignment: .topLeft,
              minWidth: pageWidth,
              maxWidth: pageWidth,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Transform.scale(
                scale: scale,
                alignment: .topLeft,
                child: Container(
                  key: const ValueKey<String>('dv-studio-thumbnail-sheet'),
                  width: pageWidth,
                  constraints: BoxConstraints(minHeight: pageHeight),
                  color: const Color(0xFFFFFFFF),
                  alignment: .topLeft,
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

/// Below this width Studio is laid out for a phone: sections along the
/// bottom, and the editor one pane at a time.
const double dvStudioPhoneWidth = 600;

/// The phone editor's panes.
enum _DVStudioPane { elements, page, style }
