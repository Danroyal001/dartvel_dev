/// Studio's incident views: the list, one incident's timeline and the actions
/// a person takes on it, and a preview of the public status page.
///
/// Every write goes through `DVIncidents` -- `update` for a note, a public
/// update or a new title, `resolve` for the end -- and a refusal or a failed
/// save is shown where it happened. What the public would see is built by
/// `DVStatusSnapshot.build`, the same call the status page reads, so a
/// preview cannot show an internal entry the page would not.
///
/// Not exported: the screen is the API, and these are its parts.
library dartvel_flutter.studio.incidents;

import 'dart:async';

// Not re-exported by the dartvel_flutter barrel, whose core exports are a
// `show` list.
import 'package:dartvel_core/dartvel.dart'
    show
        DVComponentStatus,
        DVIncident,
        DVIncidentEntry,
        DVIncidentStatus,
        DVIncidents,
        DVPublicIncident,
        DVStatusSnapshot;
import 'package:flutter/material.dart' show Icon, IconData, Icons;
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';
import 'studio_ops_parts.dart';
import 'studio_review.dart' show studioActionControl, studioBanner;

/// The incidents tab of the Operations section.
class StudioIncidentsView extends StatefulWidget {
  const StudioIncidentsView({
    super.key,
    required this.incidents,
    required this.list,
    required this.actor,
    required this.now,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
  });

  final DVIncidents? incidents;

  /// Every incident, newest first, as the section last read them.
  final List<DVIncident> list;

  /// Who writes. Null writes nothing.
  final String? actor;
  final DateTime Function() now;
  final String? selected;
  final ValueChanged<String> onSelect;

  /// Reads the incidents again, after a write or a refusal.
  final Future<void> Function() onChanged;

  @override
  State<StudioIncidentsView> createState() => _StudioIncidentsViewState();
}

enum _Mode { internal, public }

/// A refusal decided before the runtime was asked.
class _Refusal implements Exception {
  const _Refusal(this.message);
  final String message;
}

class _StudioIncidentsViewState extends State<StudioIncidentsView> {
  _Mode _mode = _Mode.internal;
  String _message = '';
  DVIncidentStatus? _moveTo;
  String? _title;
  String _resolveMessage = '';
  bool _busy = false;
  (String, String)? _error;
  String? _done;

  /// Bumped to give the inputs fresh state: after a write, or on another
  /// incident.
  int _inputs = 0;
  String? _draftFor;

  void _clearDrafts() {
    _message = '';
    _moveTo = null;
    _title = null;
    _resolveMessage = '';
    _inputs++;
  }

  bool _isOpenGroup(DVIncident i) =>
      i.status == DVIncidentStatus.investigating ||
      i.status == DVIncidentStatus.identified;

  // --- actions --------------------------------------------------------------

  Future<void> _act(
    String failTitle,
    Future<String> Function(DVIncidents incidents, String actor) action,
  ) async {
    final DVIncidents? incidents = widget.incidents;
    final String? actor = widget.actor;
    if (incidents == null || actor == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _done = null;
    });
    (String, String)? error;
    String? done;
    try {
      done = await action(incidents, actor);
    } on _Refusal catch (refusal) {
      error = (failTitle, refusal.message);
    } on ArgumentError catch (refused) {
      error = (failTitle, '${refused.message}');
    } on StateError catch (refused) {
      error = (failTitle, refused.message);
    } on Object catch (failure) {
      error = (failTitle, '$failure');
    }
    // Read again either way: a refusal usually means the incident moved, and
    // the screen should show where it is now.
    await widget.onChanged();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      _done = done;
      if (error == null) _clearDrafts();
    });
  }

  void _post(DVIncident incident) {
    final bool public = _mode == _Mode.public;
    final String message = _message.trim();
    final DVIncidentStatus? moveTo = public ? _moveTo : null;
    unawaited(
      _act(public ? 'The update was not posted' : 'The note was not added', (
        DVIncidents incidents,
        String actor,
      ) async {
        await incidents.update(
          incident.id,
          message: message,
          public: public,
          status: moveTo,
          actor: actor,
          now: widget.now(),
        );
        return public
            ? 'Posted as $actor. The status page shows it from its next '
                  'snapshot.'
            : 'Added to the timeline as $actor. It stays internal.';
      }),
    );
  }

  void _rename(DVIncident incident) {
    final String next = (_title ?? incident.title).trim();
    unawaited(
      _act('The incident was not renamed', (
        DVIncidents incidents,
        String actor,
      ) async {
        await incidents.update(
          incident.id,
          message:
              'Renamed for the public from "${incident.title}" to "$next".',
          title: next,
          actor: actor,
          now: widget.now(),
        );
        return 'Renamed. The status page calls it "$next".';
      }),
    );
  }

  void _resolve(DVIncident incident) {
    final String message = _resolveMessage.trim();
    unawaited(
      _act('The incident was not resolved', (
        DVIncidents incidents,
        String actor,
      ) async {
        // Asked of the store, not of the list this screen read: an alert or a
        // colleague may have moved it since.
        final DVIncident? current = await incidents.find(incident.id);
        if (current == null) {
          throw const _Refusal('This incident is no longer in the store.');
        }
        if (current.status != DVIncidentStatus.monitoring) {
          throw _Refusal(
            'It is ${opsIncidentLabel(current.status).toLowerCase()} now, not '
            'monitoring: it moved after this screen read it. Nothing was '
            'posted. Resolve once it is back in monitoring and the fix has held.',
          );
        }
        await incidents.resolve(
          incident.id,
          message: message,
          actor: actor,
          now: widget.now(),
        );
        return 'Resolved in public by $actor.';
      }),
    );
  }

  // --- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.incidents == null) {
      return DVStudioStyle.emptyState(
        icon: Icons.report_outlined,
        title: 'No incident store',
        message:
            'Pass DVIncidents to DVStudioScreen, or a DVAlerting that '
            'has one, to list incidents and write their timelines here.',
      );
    }
    if (widget.list.isEmpty) {
      return DVStudioStyle.emptyState(
        icon: Icons.report_outlined,
        title: 'No incidents',
        message:
            'An alert that fires opens one, and a crash spike links into '
            'the newest open one.',
      );
    }
    final DVIncident current = widget.list.firstWhere(
      (DVIncident i) => i.id == widget.selected,
      orElse: () => widget.list.firstWhere(
        (DVIncident i) => i.isOpen,
        orElse: () => widget.list.first,
      ),
    );
    if (_draftFor != current.id) {
      _draftFor = current.id;
      _mode = _Mode.internal;
      _error = null;
      _done = null;
      _clearDrafts();
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) =>
          DVStudioStyle.panes(
            listWidth: box.maxWidth < 900 ? 240 : 300,
            list: _list(current),
            detail: _detail(current),
          ),
    );
  }

  Widget _list(DVIncident current) {
    final DateTime now = widget.now();
    final List<DVIncident> open = widget.list.where(_isOpenGroup).toList();
    final List<DVIncident> monitoring = widget.list
        .where((DVIncident i) => i.status == DVIncidentStatus.monitoring)
        .toList();
    final List<DVIncident> resolved = widget.list
        .where((DVIncident i) => !i.isOpen)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: DVStudioStyle.space4),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: opsText('Incidents', size: 14, weight: FontWeight.w600),
              ),
              Flexible(
                child: opsBadge(
                  '${open.length + monitoring.length} open',
                  tone: open.isEmpty && monitoring.isEmpty
                      ? DVStudioStyle.faint
                      : DVStudioStyle.warning,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: DVStudioStyle.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _group('open', 'Open', open, current, now),
                _group('monitoring', 'Monitoring', monitoring, current, now),
                _group('resolved', 'Resolved', resolved, current, now),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _group(
    String key,
    String label,
    List<DVIncident> items,
    DVIncident current,
    DateTime now,
  ) {
    return Column(
      key: ValueKey<String>('dv-studio-incidents-$key'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: opsText(
                  label.toUpperCase(),
                  size: 10.5,
                  color: DVStudioStyle.muted,
                  weight: FontWeight.w600,
                ),
              ),
              opsText('${items.length}', size: 11, color: DVStudioStyle.faint),
            ],
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: opsText('None', size: 12, color: DVStudioStyle.faint),
          ),
        for (final DVIncident incident in items)
          _row(incident, incident.id == current.id, now),
      ],
    );
  }

  Widget _row(DVIncident incident, bool selected, DateTime now) {
    final Color tone = opsIncidentTone(incident.status);
    final bool listed = incident.timeline.any((DVIncidentEntry e) => e.public);
    return GestureDetector(
      key: ValueKey<String>('dv-studio-incident-${incident.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onSelect(incident.id),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: DVStudioStyle.space2,
            vertical: 1,
          ),
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
          decoration: BoxDecoration(
            color: selected ? DVStudioStyle.selected : const Color(0x00000000),
            borderRadius: BorderRadius.circular(DVStudioStyle.radius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(opsIncidentIcon(incident.status), size: 14, color: tone),
                  const SizedBox(width: DVStudioStyle.space2),
                  Expanded(
                    child: opsText(
                      incident.title,
                      size: 13,
                      weight: FontWeight.w600,
                      color: selected
                          ? DVStudioStyle.accent
                          : DVStudioStyle.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 22),
                child: Row(
                  children: <Widget>[
                    Flexible(
                      child: opsBadge(
                        opsIncidentLabel(incident.status),
                        tone: tone,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: opsText(
                        incident.isOpen
                            ? 'opened ${opsAgo(incident.openedAt, now)}'
                            : 'resolved '
                                  '${opsAgo(incident.resolvedAt ?? incident.openedAt, now)}',
                        size: 12,
                        color: DVStudioStyle.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (incident.isOpen && !listed)
                Padding(
                  padding: const EdgeInsets.only(left: 22, top: 4),
                  child: opsText(
                    'Not on the status page yet',
                    size: 11.5,
                    color: DVStudioStyle.faint,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- the detail -----------------------------------------------------------

  Widget _detail(DVIncident incident) {
    final DateTime now = widget.now();
    final Color tone = opsIncidentTone(incident.status);
    final String origin = incident.rules.isNotEmpty
        ? 'from alert ${incident.rules.join(', ')}'
        : incident.crashFingerprints.isNotEmpty
        ? 'from a crash spike'
        : 'opened by a person';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: DVStudioStyle.space5),
          decoration: const BoxDecoration(
            color: DVStudioStyle.surface,
            border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(DVStudioStyle.radius),
                ),
                child: Icon(
                  opsIncidentIcon(incident.status),
                  size: 17,
                  color: tone,
                ),
              ),
              const SizedBox(width: DVStudioStyle.space3),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    opsText(incident.title, size: 15, weight: FontWeight.w700),
                    const SizedBox(height: 2),
                    opsText(
                      '${incident.id} · opened ${opsTime(incident.openedAt)} '
                      '· $origin',
                      size: 12,
                      color: DVStudioStyle.muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DVStudioStyle.space2),
              Flexible(
                child: opsBadge(opsIncidentLabel(incident.status), tone: tone),
              ),
            ],
          ),
        ),
        if (_error != null)
          studioBanner(
            key: const ValueKey<String>('dv-studio-incident-error'),
            tone: DVStudioStyle.danger,
            icon: Icons.error_outline,
            title: _error!.$1,
            detail: _error!.$2,
            onDismiss: () => setState(() => _error = null),
          ),
        if (_done != null)
          studioBanner(
            key: const ValueKey<String>('dv-studio-incident-done'),
            tone: DVStudioStyle.success,
            icon: Icons.check_circle_outline,
            title: 'Saved to the incident',
            detail: _done!,
            onDismiss: () => setState(() => _done = null),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final bool wide = box.maxWidth >= 980;
              final double pad = box.maxWidth < 600
                  ? DVStudioStyle.space4
                  : DVStudioStyle.space6;
              const SizedBox gap = SizedBox(height: DVStudioStyle.space4);
              final Widget composer = _composer(incident, now);
              final Widget timeline = _timeline(incident, now);
              final Widget rename = _renameCard(incident);
              final Widget resolve = _resolveCard(incident, now);
              return SingleChildScrollView(
                padding: EdgeInsets.all(pad),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(child: timeline),
                          const SizedBox(width: DVStudioStyle.space5),
                          SizedBox(
                            width: 420,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                composer,
                                gap,
                                resolve,
                                gap,
                                rename,
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          composer,
                          gap,
                          timeline,
                          gap,
                          resolve,
                          gap,
                          rename,
                        ],
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _timeline(DVIncident incident, DateTime now) {
    final int publicCount = incident.timeline
        .where((DVIncidentEntry e) => e.public)
        .length;
    final Duration lasted = (incident.resolvedAt ?? now).difference(
      incident.openedAt,
    );
    return DVStudioStyle.card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          opsCardHeader(
            'Timeline',
            '${incident.timeline.length} entries, $publicCount public. '
                'Newest first.',
            icon: Icons.timeline,
            trailing: publicCount > 0
                ? opsBadge('On the status page', tone: DVStudioStyle.success)
                : opsBadge('Not public yet', tone: DVStudioStyle.muted),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Wrap(
              spacing: DVStudioStyle.space6,
              runSpacing: DVStudioStyle.space3,
              children: <Widget>[
                opsFact('Opened', opsTime(incident.openedAt), size: 13.5),
                opsFact(
                  incident.isOpen ? 'Open for' : 'Lasted',
                  opsShort(lasted),
                  size: 13.5,
                ),
                opsFact(
                  'Components',
                  incident.components.isEmpty
                      ? 'None named'
                      : incident.components.join(', '),
                  size: 13.5,
                  tone: incident.components.isEmpty
                      ? DVStudioStyle.muted
                      : DVStudioStyle.ink,
                ),
                if (incident.rules.isNotEmpty)
                  opsFact('Alert rules', incident.rules.join(', '), size: 13.5),
                if (incident.crashFingerprints.isNotEmpty)
                  opsFact(
                    'Crash groups',
                    '${incident.crashFingerprints.length}',
                    size: 13.5,
                  ),
              ],
            ),
          ),
          for (int i = incident.timeline.length - 1; i >= 0; i--)
            _entry(i, incident.timeline[i]),
        ],
      ),
    );
  }

  Widget _entry(int index, DVIncidentEntry entry) {
    final (IconData icon, Color tone, String author) = switch (entry.source) {
      'alert' => (
        Icons.notifications_active_outlined,
        DVStudioStyle.danger,
        entry.actor ?? 'Alert',
      ),
      'crash' => (
        Icons.bug_report_outlined,
        DVStudioStyle.warning,
        entry.actor ?? 'Crash reporting',
      ),
      _ => (
        Icons.person_outline,
        DVStudioStyle.accent,
        entry.actor ?? 'Unattributed',
      ),
    };
    return Container(
      key: ValueKey<String>('dv-studio-incident-entry-$index'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: entry.public
            ? DVStudioStyle.success.withValues(alpha: 0.03)
            : null,
        border: const Border(top: BorderSide(color: DVStudioStyle.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: tone),
          ),
          const SizedBox(width: DVStudioStyle.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    opsText(author, size: 12.5, weight: FontWeight.w600),
                    opsText(
                      opsTime(entry.at),
                      size: 12,
                      color: DVStudioStyle.faint,
                    ),
                    if (entry.status != null)
                      opsBadge(
                        '→ ${opsIncidentLabel(entry.status!)}',
                        tone: opsIncidentTone(entry.status!),
                      ),
                    opsBadge(
                      entry.public ? 'Public' : 'Internal',
                      tone: entry.public
                          ? DVStudioStyle.success
                          : DVStudioStyle.muted,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                opsText(entry.message, size: 13, maxLines: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- actions --------------------------------------------------------------

  String? get _noActor => widget.actor == null
      ? 'Studio was given no actor, so there is nobody to write this as.'
      : null;

  Widget _composer(DVIncident incident, DateTime now) {
    final bool public = _mode == _Mode.public;
    final String text = _message.trim();
    final String? reason =
        _noActor ??
        (text.isEmpty
            ? (public
                  ? 'Write the public update first.'
                  : 'Write the note first.')
            : _busy
            ? 'Saving…'
            : null);
    return DVStudioStyle.card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          opsCardHeader(
            public ? 'Post a public update' : 'Add an internal note',
            public
                ? 'Shown on the status page, word for word.'
                : 'For the people working on it. Never shown on the status '
                      'page.',
            icon: public ? Icons.campaign_outlined : Icons.edit_note,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: <Widget>[
                opsChoice(
                  key: 'dv-studio-incident-mode-internal',
                  label: 'Internal note',
                  icon: Icons.lock_outline,
                  selected: !public,
                  onTap: () => setState(() => _mode = _Mode.internal),
                ),
                opsChoice(
                  key: 'dv-studio-incident-mode-public',
                  label: 'Public update',
                  icon: Icons.public,
                  selected: public,
                  onTap: () => setState(() => _mode = _Mode.public),
                ),
              ],
            ),
          ),
          const SizedBox(height: DVStudioStyle.space3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: KeyedSubtree(
              key: const ValueKey<String>('dv-studio-incident-message'),
              child: _TextArea(
                key: ValueKey<String>('message-${incident.id}-$_inputs'),
                value: _message,
                placeholder: public
                    ? 'What is happening, in words a customer understands'
                    : 'What you found, tried or decided',
                onChanged: (String value) => setState(() => _message = value),
              ),
            ),
          ),
          if (public) ...<Widget>[
            const SizedBox(height: DVStudioStyle.space3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  opsText(
                    'MOVES IT TO',
                    size: 10.5,
                    color: DVStudioStyle.muted,
                    weight: FontWeight.w600,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: <Widget>[
                      opsChoice(
                        key: 'dv-studio-incident-status-keep',
                        label: 'Stays ${opsIncidentLabel(incident.status)}',
                        selected: _moveTo == null,
                        onTap: () => setState(() => _moveTo = null),
                      ),
                      for (final DVIncidentStatus status
                          in const <DVIncidentStatus>[
                            DVIncidentStatus.investigating,
                            DVIncidentStatus.identified,
                            DVIncidentStatus.monitoring,
                          ])
                        if (status != incident.status)
                          opsChoice(
                            key: 'dv-studio-incident-status-${status.name}',
                            label: opsIncidentLabel(status),
                            selected: _moveTo == status,
                            onTap: () => setState(() => _moveTo = status),
                          ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: DVStudioStyle.space3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: opsNote(
              key: const ValueKey<String>(
                'dv-studio-incident-internal-warning',
              ),
              tone: public ? DVStudioStyle.warning : DVStudioStyle.muted,
              icon: Icons.lock_outline,
              title: public
                  ? 'Internal notes stay internal'
                  : 'Internal notes are never public',
              body: public
                  ? 'The status page shows public updates only. This '
                        'incident\'s internal notes, and what its alerts wrote, '
                        'are not in the preview below and never reach the page.'
                  : 'The status page shows public updates only. Choose Public '
                        'update to write something customers will read.',
            ),
          ),
          if (public) ...<Widget>[
            const SizedBox(height: DVStudioStyle.space3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _publicPreview(incident, now),
            ),
          ],
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: reason == null
                      ? opsText(
                          public
                              ? 'Posted as ${widget.actor}, in public.'
                              : 'Written as ${widget.actor}.',
                          size: 12,
                          color: DVStudioStyle.faint,
                          maxLines: 2,
                        )
                      : opsText(
                          reason,
                          size: 12,
                          color: DVStudioStyle.faint,
                          maxLines: 2,
                        ),
                ),
                const SizedBox(width: DVStudioStyle.space2),
                Flexible(
                  child: studioActionControl(
                    'dv-studio-incident-post',
                    public ? 'Post public update' : 'Add note',
                    reason == null ? () => _post(incident) : null,
                    primary: true,
                    icon: public
                        ? Icons.campaign_outlined
                        : Icons.add_comment_outlined,
                    reason: reason,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The incident as the status page will show it once this update is
  /// posted: the entry the runtime would append, on a copy, run through
  /// `DVStatusSnapshot.build`.
  Widget _publicPreview(DVIncident incident, DateTime now) {
    final String text = _message.trim();
    final DVIncident draft = DVIncident.fromJson(incident.toJson());
    if (text.isNotEmpty) {
      draft.timeline.add(
        DVIncidentEntry(
          at: now,
          message: text,
          status: _moveTo,
          public: true,
          actor: widget.actor,
        ),
      );
      if (_moveTo != null) {
        draft.status = _moveTo!;
        draft.resolvedAt = null;
      }
    }
    final DVStatusSnapshot snapshot = DVStatusSnapshot.build(
      health: opsNoChecks,
      incidents: <DVIncident>[draft],
      now: now,
    );
    DVPublicIncident? shown;
    for (final DVPublicIncident candidate in snapshot.incidents) {
      if (candidate.id == incident.id) shown = candidate;
    }
    return Container(
      key: const ValueKey<String>('dv-studio-incident-public-preview'),
      padding: const EdgeInsets.all(DVStudioStyle.space3),
      decoration: BoxDecoration(
        color: DVStudioStyle.canvas,
        border: Border.all(color: DVStudioStyle.lineStrong),
        borderRadius: BorderRadius.circular(DVStudioStyle.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.public, size: 14, color: DVStudioStyle.muted),
              const SizedBox(width: 6),
              Expanded(
                child: opsText(
                  'PREVIEW · AS THE STATUS PAGE WILL SHOW IT',
                  size: 10.5,
                  color: DVStudioStyle.muted,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: DVStudioStyle.space2),
          if (shown == null)
            opsText(
              text.isEmpty
                  ? 'Not on the status page: this incident has no public '
                        'update yet. Write one to see how it will appear.'
                  : 'Not on the status page: it was resolved too long ago to '
                        'be listed.',
              size: 12,
              color: DVStudioStyle.muted,
              maxLines: 3,
            )
          else
            OpsPublicIncidentView(
              incident: shown,
              highlightLatest: text.isNotEmpty,
            ),
        ],
      ),
    );
  }

  Widget _renameCard(DVIncident incident) {
    final String next = (_title ?? incident.title).trim();
    final String? reason =
        _noActor ??
        (next.isEmpty
            ? 'Give it a title.'
            : next == incident.title
            ? 'Type the title the public should see.'
            : _busy
            ? 'Saving…'
            : null);
    return DVStudioStyle.card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          opsCardHeader(
            'Public title',
            'The status page names the incident by this. An alert names it '
                'after its rule; give it words a customer understands.',
            icon: Icons.title,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: KeyedSubtree(
                    key: const ValueKey<String>('dv-studio-incident-title'),
                    child: DVStudioTextInput(
                      key: ValueKey<String>('title-${incident.id}-$_inputs'),
                      value: incident.title,
                      placeholder: 'What customers call the problem',
                      onChanged: (String value) =>
                          setState(() => _title = value),
                    ),
                  ),
                ),
                const SizedBox(width: DVStudioStyle.space2),
                Flexible(
                  child: studioActionControl(
                    'dv-studio-incident-rename',
                    'Rename',
                    reason == null ? () => _rename(incident) : null,
                    icon: Icons.drive_file_rename_outline,
                    reason: reason,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _resolveCard(DVIncident incident, DateTime now) {
    if (incident.status == DVIncidentStatus.resolved) {
      DVIncidentEntry? closing;
      for (final DVIncidentEntry e in incident.timeline) {
        if (e.status == DVIncidentStatus.resolved) closing = e;
      }
      return DVStudioStyle.card(
        padding: EdgeInsets.zero,
        child: opsCardHeader(
          'Resolved',
          'Resolved ${opsTime(incident.resolvedAt ?? closing?.at ?? now)}'
              '${closing?.actor == null ? '' : ' by ${closing!.actor}'}.',
          icon: Icons.check_circle_outline,
        ),
      );
    }
    if (incident.status != DVIncidentStatus.monitoring ||
        widget.actor == null) {
      final bool monitoring = incident.status == DVIncidentStatus.monitoring;
      return DVStudioStyle.card(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            opsCardHeader('Resolve', null, icon: Icons.task_alt),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: opsNote(
                key: const ValueKey<String>(
                  'dv-studio-incident-resolve-unavailable',
                ),
                tone: DVStudioStyle.muted,
                icon: Icons.visibility_outlined,
                title: monitoring
                    ? 'Resolving needs a person'
                    : 'Resolve opens in monitoring',
                body: monitoring
                    ? 'Studio was given no actor. An incident is resolved by '
                          'a person, on the record.'
                    : 'This incident is '
                          '${opsIncidentLabel(incident.status).toLowerCase()}. '
                          'Resolving tells the public it is over, so it follows '
                          'a period of watching the fix hold: post an update '
                          'that moves it to monitoring first. An alert clearing '
                          'moves it there too.',
              ),
            ),
          ],
        ),
      );
    }
    DateTime? since;
    for (final DVIncidentEntry e in incident.timeline) {
      if (e.status == DVIncidentStatus.monitoring) since = e.at;
    }
    final String? reason = _resolveMessage.trim().isEmpty
        ? 'Write the closing public update first.'
        : _busy
        ? 'Saving…'
        : null;
    return DVStudioStyle.card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          opsCardHeader(
            'Resolve',
            '${since == null ? 'In monitoring' : 'In monitoring since ${opsAgo(since, now)}'}. '
                'Resolving posts this as the final public update and closes '
                'the incident, as ${widget.actor}.',
            icon: Icons.task_alt,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: KeyedSubtree(
              key: const ValueKey<String>('dv-studio-incident-resolve-message'),
              child: _TextArea(
                key: ValueKey<String>('resolve-${incident.id}-$_inputs'),
                value: _resolveMessage,
                placeholder: 'What customers should know now that it is over',
                onChanged: (String value) =>
                    setState(() => _resolveMessage = value),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: opsText(
                    reason ?? 'Shown on the status page.',
                    size: 12,
                    color: DVStudioStyle.faint,
                    maxLines: 2,
                  ),
                ),
                const SizedBox(width: DVStudioStyle.space2),
                Flexible(
                  child: studioActionControl(
                    'dv-studio-incident-resolve',
                    'Resolve incident',
                    reason == null ? () => _resolve(incident) : null,
                    icon: Icons.task_alt,
                    primary: true,
                    reason: reason,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A multi-line text input in Studio's style, with its own controller.
class _TextArea extends StatefulWidget {
  const _TextArea({
    super.key,
    required this.value,
    required this.placeholder,
    required this.onChanged,
  });

  final String value;
  final String placeholder;
  final ValueChanged<String> onChanged;

  @override
  State<_TextArea> createState() => _TextAreaState();
}

class _TextAreaState extends State<_TextArea> {
  late final TextEditingController _text = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_repaint);
    _text.addListener(_repaint);
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_repaint);
    _text.removeListener(_repaint);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _focus.requestFocus,
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: DVStudioStyle.surface,
          border: Border.all(
            color: _focus.hasFocus
                ? DVStudioStyle.accent
                : DVStudioStyle.lineStrong,
          ),
          borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
        ),
        child: Stack(
          children: <Widget>[
            if (_text.text.isEmpty)
              IgnorePointer(
                child: opsText(
                  widget.placeholder,
                  size: 13,
                  color: DVStudioStyle.faint,
                  maxLines: 2,
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: EditableText(
                controller: _text,
                focusNode: _focus,
                maxLines: null,
                minLines: 3,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(
                  fontSize: 13,
                  color: DVStudioStyle.ink,
                  height: 1.35,
                ),
                cursorColor: DVStudioStyle.accent,
                backgroundCursorColor: const Color(0xFFCCCCCC),
                onChanged: widget.onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The public status page, as the snapshot would render it, marked as a
/// preview so nobody mistakes it for the page itself.
class StudioStatusPreview extends StatelessWidget {
  const StudioStatusPreview({
    super.key,
    required this.snapshot,
    this.healthError,
  });

  final DVStatusSnapshot snapshot;
  final String? healthError;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        studioBanner(
          key: const ValueKey<String>('dv-studio-status-preview-mark'),
          tone: DVStudioStyle.accent,
          icon: Icons.visibility_outlined,
          title: 'Preview · not published',
          detail:
              'What DVStatusSnapshot.build makes from the health checks '
              'and incidents right now, drawn the way a status page shows it. '
              'Only public updates appear, and checks show a status without '
              'their detail. Nothing on this tab is published.',
        ),
        if (healthError != null)
          studioBanner(
            key: const ValueKey<String>('dv-studio-status-health-error'),
            tone: DVStudioStyle.warning,
            icon: Icons.monitor_heart_outlined,
            title: 'Health checks could not be read',
            detail: '$healthError. Components are left out of this preview.',
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final double pad = box.maxWidth < 600
                  ? DVStudioStyle.space4
                  : DVStudioStyle.space8;
              return SingleChildScrollView(
                padding: EdgeInsets.all(pad),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: _page(box.maxWidth < 600),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _page(bool narrow) {
    final DVComponentStatus overall = snapshot.overall;
    final Color tone = opsComponentTone(overall);
    final List<DVPublicIncident> active = snapshot.incidents
        .where((DVPublicIncident i) => i.status != DVIncidentStatus.resolved)
        .toList();
    final List<DVPublicIncident> past = snapshot.incidents
        .where((DVPublicIncident i) => i.status == DVIncidentStatus.resolved)
        .toList();
    const SizedBox section = SizedBox(height: DVStudioStyle.space6);
    return Container(
      key: const ValueKey<String>('dv-studio-status-preview'),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        border: Border.all(color: DVStudioStyle.line),
        borderRadius: BorderRadius.circular(DVStudioStyle.radiusLarge),
        boxShadow: DVStudioStyle.shadowLarge,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F7FA),
              border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(DVStudioStyle.radiusLarge),
              ),
            ),
            child: Row(
              children: <Widget>[
                for (final Color c in const <Color>[
                  Color(0xFFFF5F57),
                  Color(0xFFFEBC2E),
                  Color(0xFF28C840),
                ]) ...<Widget>[
                  DVStudioStyle.dot(c, size: 9),
                  const SizedBox(width: 5),
                ],
                const SizedBox(width: DVStudioStyle.space2),
                Expanded(
                  child: Container(
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFFFF),
                      border: Border.all(color: DVStudioStyle.line),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: opsText(
                      'Status page · public view',
                      size: 11,
                      color: DVStudioStyle.faint,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(narrow ? 16 : 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                opsText('System status', size: 22, weight: FontWeight.w700),
                const SizedBox(height: 4),
                opsText(
                  'Updated ${opsTime(snapshot.generatedAt)}',
                  size: 12.5,
                  color: DVStudioStyle.muted,
                ),
                const SizedBox(height: DVStudioStyle.space5),
                Container(
                  padding: const EdgeInsets.all(DVStudioStyle.space4),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.10),
                    border: Border.all(color: tone.withValues(alpha: 0.35)),
                    borderRadius: BorderRadius.circular(DVStudioStyle.radius),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        switch (overall) {
                          DVComponentStatus.operational => Icons.check_circle,
                          DVComponentStatus.degraded => Icons.error,
                          DVComponentStatus.outage => Icons.cancel,
                        },
                        size: 22,
                        color: tone,
                      ),
                      const SizedBox(width: DVStudioStyle.space3),
                      Expanded(
                        child: opsText(
                          switch (overall) {
                            DVComponentStatus.operational =>
                              'All systems operational',
                            DVComponentStatus.degraded =>
                              'Degraded performance',
                            DVComponentStatus.outage => 'Major outage',
                          },
                          size: 16,
                          weight: FontWeight.w700,
                          color: tone,
                        ),
                      ),
                    ],
                  ),
                ),
                if (active.isNotEmpty) ...<Widget>[
                  section,
                  opsText(
                    'Active incidents',
                    size: 15,
                    weight: FontWeight.w700,
                  ),
                  const SizedBox(height: DVStudioStyle.space3),
                  for (final DVPublicIncident incident in active) ...<Widget>[
                    OpsPublicIncidentView(
                      key: ValueKey<String>(
                        'dv-studio-status-incident-${incident.id}',
                      ),
                      incident: incident,
                    ),
                    const SizedBox(height: DVStudioStyle.space3),
                  ],
                ],
                section,
                opsText('Components', size: 15, weight: FontWeight.w700),
                const SizedBox(height: DVStudioStyle.space3),
                if (snapshot.components.isEmpty)
                  opsText(
                    'No health checks are registered, so no components are '
                    'listed.',
                    size: 13,
                    color: DVStudioStyle.muted,
                    maxLines: 2,
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: DVStudioStyle.line),
                      borderRadius: BorderRadius.circular(DVStudioStyle.radius),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (final MapEntry<String, DVComponentStatus> c
                            in snapshot.components.entries)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              border: c.key == snapshot.components.keys.first
                                  ? null
                                  : const Border(
                                      top: BorderSide(
                                        color: DVStudioStyle.line,
                                      ),
                                    ),
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: opsText(
                                    c.key,
                                    size: 13.5,
                                    weight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: DVStudioStyle.space2),
                                Flexible(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      DVStudioStyle.dot(
                                        opsComponentTone(c.value),
                                        size: 8,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: opsText(
                                          opsComponentLabel(c.value),
                                          size: 12.5,
                                          weight: FontWeight.w600,
                                          color: opsComponentTone(c.value),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                section,
                opsText('Past incidents', size: 15, weight: FontWeight.w700),
                const SizedBox(height: DVStudioStyle.space3),
                if (past.isEmpty)
                  opsText(
                    'No incidents resolved in the last 7 days.',
                    size: 13,
                    color: DVStudioStyle.muted,
                  )
                else
                  for (final DVPublicIncident incident in past) ...<Widget>[
                    OpsPublicIncidentView(
                      key: ValueKey<String>(
                        'dv-studio-status-incident-${incident.id}',
                      ),
                      incident: incident,
                    ),
                    const SizedBox(height: DVStudioStyle.space3),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
