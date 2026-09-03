import 'package:dartvel_example_notes/dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

/// The module's own home page.
///
/// It says nothing about where it is mounted: the parent decides that, and a
/// module that hard-coded its mount point could not be mounted twice.
@DVPage(title: 'Notes')
@pragma('vm:entry-point')
Widget _notesIndexPage(BuildContext context) => const DVBox.list(<Widget>[
      DVText('Notes'),
      DVText('A module, mounted into the example application.'),
    ]);
