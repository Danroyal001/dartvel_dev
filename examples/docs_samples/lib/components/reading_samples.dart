import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

// docs:start models-device-use
// The reader's choice, kept for their next visit.
void preferSerif(bool serif) => ReadingSettings.kept.copyWith(serif: serif).keep();

// A widget that reads it rebuilds when it changes.
@DVFunctionalWidget()
Widget _readingScale(BuildContext context) =>
    DVText('Text at ${context.global<ReadingSettings>().scale}x');
// docs:end
