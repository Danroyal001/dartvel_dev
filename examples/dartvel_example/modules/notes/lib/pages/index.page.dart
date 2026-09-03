import 'package:dartvel_example_notes/dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

/// Where this module's logo is now.
///
/// Public because the generated router carries the page's body: a private
/// helper cannot be seen from there.
///
/// Mounted, a parent serves it under `packages/<name>/`; standing alone the
/// module serves it itself. Asking the registry rather than writing either
/// path is what keeps the mount point out of module code -- the same module
/// is mounted at `/notes` here and could be mounted anywhere else.
String notesLogo() =>
    DV.Modules.maybeGet('notes')?.asset('assets/logo.png') ?? 'assets/logo.png';

/// The module's own home page.
///
/// It says nothing about where it is mounted: the parent decides that, and a
/// module that hard-coded its mount point could not be mounted twice.
@DVPage(title: 'Notes')
@pragma('vm:entry-point')
Widget _notesIndexPage(BuildContext context) => DVBox.list(<Widget>[
      Image.asset(notesLogo(), width: 32, height: 32),
      const DVText('Notes'),
      const DVText('A module, mounted into the example application.'),
    ]);
