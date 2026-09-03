// The kiosk's screen-side half.
//
// The runtime owns the session clock; this is its hands. Any pointer or key
// under it is activity; the countdown shows while the runtime is warning;
// a reset sends the application home through the callback it was given;
// and a restart loop the watchdog reports (DV-KIOSK-008) replaces the page
// with the diagnostics screen, so a device that cannot stay up shows an
// operator why instead of an attract loop that keeps dying.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart' show DVKioskReset, DVKioskRuntime;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DVKioskHost extends StatefulWidget {
  final DVKioskRuntime runtime;

  /// Where to go on a reset: the policy's home route.
  final void Function(String route) onHome;

  final Widget child;

  const DVKioskHost({
    super.key,
    required this.runtime,
    required this.onHome,
    required this.child,
  });

  /// The restart-loop finding, if the watchdog reported one. One for the
  /// application: whichever host is on screen shows it.
  static final ValueNotifier<String?> restartLoop = ValueNotifier<String?>(null);

  /// For the device binding: the watchdog found a restart loop.
  static void reportRestartLoop(String finding) => restartLoop.value = finding;

  /// An operator has seen the diagnostics and cleared them.
  static void clearRestartLoop() => restartLoop.value = null;

  @override
  State<DVKioskHost> createState() => _DVKioskHostState();
}

class _DVKioskHostState extends State<DVKioskHost> {
  StreamSubscription<DVKioskReset>? _resets;

  @override
  void initState() {
    super.initState();
    _listen(widget.runtime);
    DVKioskHost.restartLoop.addListener(_changed);
    // Every key, whatever has focus: the host is not in the focus chain of
    // a page that holds it, and activity is activity.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) widget.runtime.touch();
    return false;
  }

  @override
  void didUpdateWidget(DVKioskHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtime != widget.runtime) {
      _unlisten(oldWidget.runtime);
      _listen(widget.runtime);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _unlisten(widget.runtime);
    DVKioskHost.restartLoop.removeListener(_changed);
    super.dispose();
  }

  void _listen(DVKioskRuntime runtime) {
    runtime.countdown.addListener(_changed);
    runtime.state.addListener(_changed);
    _resets = runtime.resets.listen((DVKioskReset reset) => widget.onHome(reset.home));
  }

  void _unlisten(DVKioskRuntime runtime) {
    runtime.countdown.removeListener(_changed);
    runtime.state.removeListener(_changed);
    unawaited(_resets?.cancel());
    _resets = null;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final String? loop = DVKioskHost.restartLoop.value;
    if (loop != null) return DVKioskDiagnosticsScreen(finding: loop);
    if (!widget.runtime.policy.enabled) return widget.child;
    final Duration? left = widget.runtime.countdown.value;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.runtime.touch(),
      onPointerMove: (_) => widget.runtime.touch(),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          widget.child,
          if (left != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _DVKioskCountdown(left: left),
            ),
        ],
      ),
    );
  }
}

class _DVKioskCountdown extends StatelessWidget {
  final Duration left;

  const _DVKioskCountdown({required this.left});

  @override
  Widget build(BuildContext context) {
    final int seconds = (left.inMilliseconds / 1000).ceil();
    return Material(
      key: const ValueKey<String>('dv-kiosk-countdown'),
      color: Theme.of(context).colorScheme.inverseSurface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Still there? Starting over in $seconds s.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.onInverseSurface, fontSize: 18),
        ),
      ),
    );
  }
}

/// What an operator sees when the device cannot stay up: the finding, and
/// a way to clear it once the cause is fixed.
class DVKioskDiagnosticsScreen extends StatelessWidget {
  final String finding;

  const DVKioskDiagnosticsScreen({super.key, required this.finding});

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey<String>('dv-kiosk-diagnostics'),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text('This kiosk keeps restarting', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(finding),
              const SizedBox(height: 12),
              const Text('The application is being held here rather than restarted again. '
                  'Check the device diagnostics, fix the cause, then clear this screen.'),
              const SizedBox(height: 24),
              const FilledButton(
                key: ValueKey<String>('dv-kiosk-diagnostics-clear'),
                onPressed: DVKioskHost.clearRestartLoop,
                child: Text('Cleared, start again'),
              ),
            ],
          ),
        ),
      );
}
