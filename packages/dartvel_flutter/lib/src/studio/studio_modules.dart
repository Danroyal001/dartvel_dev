/// The modules an application mounts, and how to add one.
///
/// A module is a whole Dartvel application mounted inside another, and Studio
/// had no section for them: a module's pages showed up in the Site map with
/// no way to learn which module they came from, where it was mounted, or that
/// a declared module had failed to mount at all.
///
/// Read from the project graph the build writes beside Studio, which is the
/// one place a running server knows this from. A module that failed to mount
/// is in that file on purpose, so it is in this section too.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../dartvel_flutter.dart';

/// One module, as the graph records it.
class DVStudioModule {
  const DVStudioModule({
    required this.id,
    required this.package,
    required this.mount,
    required this.source,
    required this.deployment,
    required this.mounted,
    required this.pages,
    required this.data,
    this.version,
    this.location,
    this.fromPackage = false,
    this.problems = const <String>[],
  });

  final String id;
  final String package;
  final String mount;
  final String source;
  final String deployment;

  /// Whether the build could honour the declaration.
  final bool mounted;
  final int pages;
  final String data;
  final String? version;
  final String? location;
  final bool fromPackage;
  final List<String> problems;

  /// One from a `graph.json` entry. Unknown keys are ignored, so a graph
  /// written by a newer build opens here instead of failing.
  factory DVStudioModule.fromJson(Map<String, Object?> json) => DVStudioModule(
        id: '${json['id'] ?? ''}',
        package: '${json['package'] ?? ''}',
        mount: '${json['mount'] ?? '/'}',
        source: '${json['source'] ?? ''}',
        deployment: '${json['deployment'] ?? 'embedded'}',
        mounted: json['mounted'] != false,
        pages: json['pages'] is int ? json['pages']! as int : 0,
        data: '${json['data'] ?? 'shared'}',
        version: json['version'] as String?,
        location: json['location'] as String?,
        fromPackage: json['fromPackage'] == true,
        problems: <String>[
          for (final Object? problem
              in (json['problems'] as List?) ?? const <Object?>[])
            '$problem',
        ],
      );

  /// What the deployment means in the words a site owner reads.
  String get deploymentLabel => switch (deployment) {
        'federated' => 'Runs elsewhere',
        'splitBackend' || 'split-backend' => 'Its own backend',
        _ => 'In this app',
      };

  /// What the data mode means in those words.
  String get dataLabel => switch (data) {
        'schema-isolated' || 'schemaIsolated' => 'Its own tables',
        'database-isolated' || 'databaseIsolated' => 'Its own database',
        'remote' => 'Its own deployment',
        _ => "This app's tables",
      };
}

/// Studio's Modules section.
class DVStudioModulesSection extends StatefulWidget {
  const DVStudioModulesSection({super.key, required this.manifest});

  /// The project graph the build wrote beside Studio.
  final Future<Map<String, Object?>> Function() manifest;

  @override
  State<DVStudioModulesSection> createState() => _DVStudioModulesSectionState();
}

class _DVStudioModulesSectionState extends State<DVStudioModulesSection> {
  List<DVStudioModule>? _modules;
  String? _error;

  /// Whether the panel that says how to add one is open.
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final Map<String, Object?> graph = await widget.manifest();
      final List<DVStudioModule> modules = <DVStudioModule>[
        for (final Object? entry
            in (graph['modules'] as List?) ?? const <Object?>[])
          if (entry is Map) DVStudioModule.fromJson(entry.cast<String, Object?>()),
      ];
      if (mounted) {
        setState(() {
          _modules = modules;
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<DVStudioModule>? modules = _modules;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DVStudioStyle.panelHeader(
          title: 'Modules',
          subtitle: modules == null
              ? null
              : '${modules.length} declared in this app',
          actions: <Widget>[
            DVStudioIconButton(
              key: const ValueKey<String>('dv-studio-module-add'),
              icon: Icons.add,
              tooltip: 'Add a module',
              onTap: () => setState(() => _adding = !_adding),
            ),
            DVStudioIconButton(
              key: const ValueKey<String>('dv-studio-modules-refresh'),
              icon: Icons.refresh,
              tooltip: 'Refresh',
              onTap: () => unawaited(_load()),
            ),
          ],
        ),
        Expanded(
          child: modules == null
              ? (_error == null
                  ? DVStudioStyle.placeholder('Loading modules…')
                  : DVStudioStyle.emptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'The server did not answer',
                      message: '$_error',
                    ))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(DVStudioStyle.space5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (_adding) ...<Widget>[
                        const _DVStudioModuleImport(),
                        const SizedBox(height: DVStudioStyle.space5),
                      ],
                      if (modules.isEmpty)
                        _empty()
                      else
                        ...<Widget>[
                          for (final DVStudioModule module in modules) ...<Widget>[
                            _DVStudioModuleCard(module: module),
                            const SizedBox(height: DVStudioStyle.space3),
                          ],
                        ],
                      const SizedBox(height: DVStudioStyle.space5),
                      const _DVStudioModuleMarketplace(),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _empty() => DVStudioStyle.card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DVStudioStyle.heading('No modules in this app yet'),
            const SizedBox(height: DVStudioStyle.space2),
            DVStudioStyle.body(
              'A module is a whole Dartvel app with its own pages, data and '
              'backend. Mount one at a path and this app serves all of it: '
              'a shop under /store, a help centre under /help, the same '
              'checkout in three products. Add opens the declaration to '
              'paste into your pubspec.',
            ),
          ],
        ),
      );
}

/// One module's card.
class _DVStudioModuleCard extends StatelessWidget {
  const _DVStudioModuleCard({required this.module});

  final DVStudioModule module;

  @override
  Widget build(BuildContext context) {
    return DVStudioStyle.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: DVStudioStyle.heading(module.id)),
              if (!module.mounted)
                DVStudioStyle.badge('Not mounted',
                    tone: DVStudioStyle.danger)
              else
                DVStudioStyle.badge(module.deploymentLabel),
            ],
          ),
          const SizedBox(height: DVStudioStyle.space2),
          DVBox.wrapLine(<Widget>[
            _fact('Served at', module.mount),
            _fact(module.fromPackage ? 'Package' : 'From', module.source),
            if (module.version != null) _fact('Version', module.version!),
            _fact('Pages', '${module.pages}'),
            _fact('Data', module.dataLabel),
            if (module.location != null) _fact('Answers from', module.location!),
          ], spacing: DVStudioStyle.space5),
          if (module.problems.isNotEmpty) ...<Widget>[
            const SizedBox(height: DVStudioStyle.space3),
            for (final String problem in module.problems)
              DVStudioStyle.banner(
                tone: DVStudioStyle.danger,
                icon: Icons.error_outline,
                child: DVText(problem)
                    .modifier(const DVModifier().fontSize(13)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _fact(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DVStudioStyle.caption(label),
          DVStudioStyle.body(value),
        ],
      );
}

/// How to bring a module in from anywhere.
///
/// The declaration to paste, and not a form that writes it. A build reads
/// `pubspec.yaml`, that file is versioned, and a panel editing it behind your
/// back is a change with no diff and no review. Showing the three shapes is
/// what makes "from anywhere" concrete: a folder beside the project, a
/// package from pub, or a git repository.
class _DVStudioModuleImport extends StatelessWidget {
  const _DVStudioModuleImport();

  @override
  Widget build(BuildContext context) {
    return DVStudioStyle.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DVStudioStyle.heading('Add a module'),
          const SizedBox(height: DVStudioStyle.space2),
          DVStudioStyle.body(
            'Put one of these in your pubspec.yaml and run dartvel dev. The '
            'file is versioned, so Studio shows the declaration instead of '
            'writing it for you.',
          ),
          const SizedBox(height: DVStudioStyle.space4),
          _snippet('A folder beside this project', <String>[
            'dartvel:',
            '  modules:',
            '    notes:',
            '      source:',
            '        path: modules/notes',
            '      mount: /notes',
          ]),
          const SizedBox(height: DVStudioStyle.space3),
          _snippet('A package from pub.dev', <String>[
            'dartvel:',
            '  modules:',
            '    shop:',
            '      source:',
            '        package: acme_shop',
            '      mount: /store',
          ]),
          const SizedBox(height: DVStudioStyle.space3),
          _snippet('A git repository, anywhere', <String>[
            'dartvel:',
            '  modules:',
            '    help:',
            '      source:',
            '        git:',
            '          url: https://github.com/acme/help_module.git',
            '          ref: v2.1.0',
            '      mount: /help',
          ]),
        ],
      ),
    );
  }

  Widget _snippet(String label, List<String> lines) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DVStudioStyle.caption(label),
          const SizedBox(height: DVStudioStyle.space1),
          DVBox(
            DVBox.list(<Widget>[
              for (final String line in lines)
                DVText(line).modifier(const DVModifier()
                    .fontSize(12)
                    .fontFamily('RobotoMono')
                    .color(DVStudioStyle.ink)),
            ], spacing: 1, crossAlign: DVCrossAlign.start),
            const DVModifier()
                .width(double.infinity)
                .padding(DVStudioStyle.space3)
                .backgroundColor(DVStudioStyle.canvas)
                .border(const Border.fromBorderSide(
                    BorderSide(color: DVStudioStyle.line)))
                .rounded(DVStudioStyle.radius),
          ),
        ],
      );
}

/// The marketplace, named and honestly marked.
///
/// It is the plugin shelf a Bubble or Webflow user expects, and it is not
/// running. A section that implied it was would send somebody looking for a
/// page that does not exist.
class _DVStudioModuleMarketplace extends StatelessWidget {
  const _DVStudioModuleMarketplace();

  @override
  Widget build(BuildContext context) {
    return DVStudioStyle.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: DVStudioStyle.heading('Marketplace')),
              DVStudioStyle.badge('Not open yet',
                  tone: DVStudioStyle.warning),
            ],
          ),
          const SizedBox(height: DVStudioStyle.space2),
          DVStudioStyle.body(
            'A public shelf of modules anyone can publish to and mount in one '
            'line: a booking flow, a help centre, a storefront. It is not '
            'open yet. Until it is, a module from a git URL or a pub package '
            'works the same way and needs nobody\'s permission.',
          ),
        ],
      ),
    );
  }
}
