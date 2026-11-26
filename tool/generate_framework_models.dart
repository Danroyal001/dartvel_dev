// Writes the framework's own device models (@DVModel(storage:
// DVModelStorage.device)) with the emitter applications use, so the
// framework eats its own cooking. Run from the repository root:
//
//   dart run tool/generate_framework_models.dart
//
// packages/dartvel_cli/test/device_model_generation_test.dart fails when a
// checked-in output differs from what this writes.
import 'dart:io';

import 'package:dartvel_cli/src/generators/device_model_generator.dart';

void main() {
  for (final DVFrameworkDeviceModel model in dvFrameworkDeviceModels) {
    final String source = File(model.input).readAsStringSync();
    File(model.output).writeAsStringSync(dvFrameworkDeviceModelSource(model, source));
    stdout.writeln('wrote ${model.output}');
  }
}
