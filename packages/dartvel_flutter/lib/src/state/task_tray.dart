/// The background-task tray every page carries.
///
/// Uploads, exports and imports report typed progress; the tray is the
/// rendering of the named ones -- [DVTrayTasks], which a `DV.Workers` run
/// given a `label:` joins -- in the page shell, so no page has to remember
/// it. It is not exported, so no page can be told to add it, and it shows
/// nothing while nothing runs.
library dartvel_flutter.state.task_tray;

import 'dart:async';

import 'package:dartvel_core/dartvel.dart' show DVTrayTask, DVTrayTasks;
import 'package:dartvel_flutter/dartvel_flutter.dart'
    show DV, DVFrameworkStrings;
import 'package:flutter/material.dart';

/// The tray over [tasks], the process's registry unless a test gives one.
class DVTaskTray extends StatefulWidget {
  const DVTaskTray({super.key, this.tasks});

  final DVTrayTasks? tasks;

  @override
  State<DVTaskTray> createState() => _DVTaskTrayState();
}

class _DVTaskTrayState extends State<DVTaskTray> {
  StreamSubscription<void>? _changes;

  DVTrayTasks get _tasks => widget.tasks ?? DVTrayTasks.current;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(DVTaskTray oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tasks != widget.tasks) {
      unawaited(_changes?.cancel());
      _listen();
    }
  }

  void _listen() {
    _changes = _tasks.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<DVTrayTask> active = _tasks.active;
    if (active.isEmpty) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    return Material(
      elevation: 3,
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: .circular(8),
      child: Padding(
        padding: const .all(12),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[for (final DVTrayTask task in active) _row(task, theme)],
        ),
      ),
    );
  }

  Widget _row(DVTrayTask task, ThemeData theme) {
    final double? fraction = task.progress?.fraction;
    final String? percent = fraction == null ? null : '${(fraction * 100).round()}';
    final String spoken = percent == null
        ? task.label
        : DV.I18n.t(
            DVFrameworkStrings.taskProgress,
            args: <String, String>{'label': task.label, 'percent': percent},
          );
    return Semantics(
      container: true,
      liveRegion: true,
      label: spoken,
      excludeSemantics: true,
      child: Padding(
        padding: const .symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: .stretch,
          mainAxisSize: .min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(task.label, style: theme.textTheme.bodyMedium)),
                if (percent != null) Text('$percent%', style: theme.textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: 6),
            // Indeterminate until the first report: 0% would say the work
            // has not started when it is only quiet.
            LinearProgressIndicator(value: fraction),
          ],
        ),
      ),
    );
  }
}
