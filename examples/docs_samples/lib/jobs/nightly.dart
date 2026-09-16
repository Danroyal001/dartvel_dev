import 'package:dartvel_core/dartvel.dart';

// docs:start jobs-cron
// A cron function is public. Every other generation input is private.
@DVBackendCron('0 3 * * *', catchUp: true)
Future<void> nightlyRollup() => rollUpYesterday();
// docs:end

Future<void> rollUpYesterday() async {}
