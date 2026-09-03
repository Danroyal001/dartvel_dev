import 'package:dartvel_example_notes/dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

/// One note, at the module's own `/view/:id` and the parent's
/// `/notes/view/:id`.
@DVPage(title: 'A note')
@pragma('vm:entry-point')
Widget _notePage(BuildContext context) => const DVBox.list(<Widget>[
      DVText('A note'),
    ]);
