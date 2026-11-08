// `dartvel meters list`: what is metered, in what unit, and what bounds it,
// read from the declarations rather than from a running deployment.
import 'dart:io';

import 'package:dartvel_cli/src/commands/meters_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dv_meters_cmd_'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String relative, String contents) {
    final File file = File(p.joinAll(<String>[root.path, ...relative.split('/')]));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  test('every declared meter, with its kind, unit, limit and behaviour',
      () async {
    write('lib/meters.dart', '''
import 'package:dartvel_core/dartvel.dart';
abstract class _Meters {
  @DVMeter(unit: 'call', limit: DVLimit.entitlement, atLimit: DVQuota.throttle, notifyAt: <double>[0.8])
  static const apiCalls = DVMeter.counter;

  @DVMeter(unit: 'GB-month', gaugeBilling: DVGaugeBilling.peak)
  static const storedBytes = DVMeter.gauge;
}
''');
    final String out = await dvMetersList(root: root.path);
    final List<String> lines = out.split('\n');
    expect(lines.first, matches(RegExp(r'^METER\s+KIND\s+UNIT\s+LIMIT\s+AT LIMIT\s+DECLARED IN$')));
    expect(
        lines.firstWhere((String l) => l.startsWith('apiCalls')),
        matches(RegExp(r'^apiCalls\s+counter\s+call\s+entitlement\s+throttle\s+lib/meters\.dart$')));
    expect(
        lines.firstWhere((String l) => l.startsWith('storedBytes')),
        matches(RegExp(r'^storedBytes\s+gauge \(peak\)\s+GB-month\s+none\s+-\s+lib/meters\.dart$')));
    expect(out, endsWith('2 meters declared.'));
  });

  test('a project with no meters says how to declare one', () async {
    write('lib/main.dart', 'void main() {}\n');
    expect(await dvMetersList(root: root.path), contains('@DVMeter'));
  });

  test('a fixed limit shows its quantity', () async {
    write('lib/meters.dart', '''
import 'package:dartvel_core/dartvel.dart';
abstract class _Meters {
  @DVMeter(unit: 'message', limit: DVLimit.fixed(500), atLimit: DVQuota.block)
  static const messages = DVMeter.counter;
}
''');
    expect(await dvMetersList(root: root.path),
        matches(RegExp(r'messages\s+counter\s+message\s+500\s+block')));
  });
}
