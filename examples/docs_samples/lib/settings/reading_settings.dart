// ignore_for_file: unused_element, unused_element_parameter
import 'package:dartvel_core/dartvel.dart';

// docs:start models-device
/// How a reader likes articles set. Kept on their device, not in the
/// database: no table, page or admin. Declared outside lib/models.
@DVModel(storage: DVModelStorage.device)
class const _ReadingSettings({
  final double scale = 1.0,
  final bool serif = false,
});
// docs:end
