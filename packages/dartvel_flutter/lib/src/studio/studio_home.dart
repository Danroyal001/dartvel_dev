import 'package:dartvel_core/dartvel.dart'
    show
        DVStudioOverview,
        DVStudioHealthCheck,
        DVStudioActivity,
        dvStudioGlanceOrder,
        dvStudioGlanceLine,
        dvStudioHealthWords,
        dvStudioQuickActions;
import 'package:flutter/material.dart';

import 'studio_screen.dart';
import 'studio_server.dart';
import 'studio_style.dart';

/// The project's overview, using the same data and words as its document.
class const DVStudioHomeSection({
  super.key,
  required final DVStudioClient client,
  required final void Function(String path) open,
}) extends StatefulWidget {
  @override
  State<DVStudioHomeSection> createState() => _DVStudioHomeSectionState();
}

class _DVStudioHomeSectionState extends State<DVStudioHomeSection> {
  late Future<DVStudioOverview> _overview;
  String? _error;

  Future<DVStudioOverview> _read() async {
    _error = null;
    try {
      return await widget.client.overview();
    } on Object catch (error) {
      _error = '$error';
      return const DVStudioOverview();
    }
  }

  @override
  void initState() {
    super.initState();
    _overview = _read();
  }

  void _go(String screen, [String? object]) =>
      DVStudioNavigation.maybeOf(context)?.open(screen, object);

  Widget _group({required String label, required List<Widget> children}) =>
      Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          DVStudioStyle.heading(label),
          const SizedBox(height: 12),
          for (final Widget child in children) ...<Widget>[
            child,
            const SizedBox(height: 8),
          ],
        ],
      );

  Widget _action(String label, VoidCallback run) =>
      _HomeButton(label: label, run: run);

  static String _ago(int at) {
    final Duration elapsed = DateTime.now().toUtc().difference(
      DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
    );
    if (elapsed.inMinutes < 1) return 'Just now';
    if (elapsed.inHours < 1) {
      return '${elapsed.inMinutes} minute${elapsed.inMinutes == 1 ? '' : 's'} ago';
    }
    if (elapsed.inDays < 1) {
      return '${elapsed.inHours} hour${elapsed.inHours == 1 ? '' : 's'} ago';
    }
    return '${elapsed.inDays} day${elapsed.inDays == 1 ? '' : 's'} ago';
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey<String>('dv-studio-home'),
    padding: const .all(24),
    child: FutureBuilder<DVStudioOverview>(
      future: _overview,
      builder: (BuildContext context, AsyncSnapshot<DVStudioOverview> snapshot) {
        if (_error != null) {
          return Column(
            crossAxisAlignment: .start,
            children: <Widget>[
              DVStudioStyle.heading('Home could not be read'),
              Text(_error!),
              const SizedBox(height: 16),
              _action(
                'Try again',
                () => setState(() {
                  _overview = _read();
                }),
              ),
            ],
          );
        }
        final DVStudioOverview? overview = snapshot.data;
        if (overview == null) return const Text('Reading Home…');
        return Column(
          crossAxisAlignment: .start,
          children: <Widget>[
            DVStudioStyle.heading('Home'),
            const SizedBox(height: 24),
            _group(
              label: 'At a glance',
              children: <Widget>[
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    for (final String key in dvStudioGlanceOrder)
                      if (overview.glance[key] case final int count)
                        if (dvStudioGlanceLine(key, count) case final line?)
                          _action(line.words, () => _go(line.screen)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            _group(
              label: 'Site health',
              children: <Widget>[
                if (overview.health.isEmpty)
                  const Text('No health checks reported.'),
                for (final DVStudioHealthCheck check in overview.health)
                  Semantics(
                    label:
                        '${check.title}: ${dvStudioHealthWords(check.status)}. ${check.detail}',
                    excludeSemantics: true,
                    child: DVStudioStyle.card(
                      child: Column(
                        crossAxisAlignment: .start,
                        children: <Widget>[
                          Text(check.title),
                          Text(dvStudioHealthWords(check.status)),
                          Text(check.detail),
                          if (check.screen case final String screen)
                            _action('Open ${check.title}', () => _go(screen)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            _group(
              label: 'Recent changes',
              children: <Widget>[
                if (overview.recent.isEmpty)
                  const Text('No changes made in Studio yet.'),
                for (final DVStudioActivity activity in overview.recent)
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: .center,
                    children: <Widget>[
                      _action(
                        activity.label,
                        () => _go(activity.screen, activity.object),
                      ),
                      Text('${activity.kind} ${activity.action}'),
                      Text(_ago(activity.at)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 24),
            _group(
              label: 'Quick actions',
              children: <Widget>[
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    for (final action in dvStudioQuickActions)
                      _action(action.label, () => _go(action.screen)),
                    _action('View the site', () => widget.open('/')),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

/// A named button whose focus is exposed with its action to assistive tools.
class const _HomeButton({
  required final String label,
  required final VoidCallback run,
}) extends StatefulWidget {
  @override
  State<_HomeButton> createState() => _HomeButtonState();
}

class _HomeButtonState extends State<_HomeButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    button: true,
    enabled: true,
    focusable: true,
    focused: _focused,
    onTap: widget.run,
    child: Actions(
      actions: dvStudioActivate(widget.run),
      child: Focus(
        includeSemantics: false,
        onFocusChange: (bool focused) => setState(() => _focused = focused),
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: widget.run,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: ExcludeSemantics(
              child: DVStudioStyle.tooltip(
                widget.label,
                DVStudioStyle.control(
                  widget.label,
                  enabled: true,
                  focused: _focused,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
