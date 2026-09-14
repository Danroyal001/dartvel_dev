// `dartvel doctor` on dartvel.memory.
//
// The specification says doctor validates the configured budget against the
// device profile's declared RAM. A budget larger than the device has is a
// number the build accepts and the device can never secure: the arena comes
// up short on every launch and the only trace is a warning on the device.
import 'package:dartvel_cli/src/doctor/memory_check.dart';
import 'package:test/test.dart';

void main() {
  test('nothing declared says nothing', () {
    final DVMemoryCheck check = DVMemoryCheck.run(
      <String, Object?>{},
      const <String>['linux'],
    );
    expect(check.ok, isTrue);
    expect(check.lines, isEmpty);
  });

  test('a budget larger than the profile RAM fails, naming both', () {
    final DVMemoryCheck check = DVMemoryCheck.run(<String, Object?>{
      'memory': <String, Object?>{
        'targets': <String, Object?>{
          'sony-elinux': <String, Object?>{'budget': '2GB'},
        },
      },
      'deviceProfiles': <String, Object?>{
        'lobby-display': <String, Object?>{
          'platform': 'sony-elinux',
          'ram': '1GB',
        },
      },
    }, const <String>[]);
    expect(check.ok, isFalse);
    final String out = check.lines.join('\n');
    expect(out, contains('lobby-display'));
    expect(out, contains('2GB'));
    expect(out, contains('1GB'));
  });

  test('a profile override that fits passes, though the target budget would '
      'not', () {
    final DVMemoryCheck check = DVMemoryCheck.run(<String, Object?>{
      'memory': <String, Object?>{'budget': '4GB'},
      'deviceProfiles': <String, Object?>{
        'lobby-display': <String, Object?>{
          'platform': 'sony-elinux',
          'ram': '1GB',
          'memory': <String, Object?>{'budget': '256MB'},
        },
      },
    }, const <String>[]);
    expect(check.ok, isTrue, reason: check.lines.join('\n'));
    expect(check.lines.join('\n'), contains('256MB'));
  });

  test('RAM with no platform is said, not silently skipped', () {
    final DVMemoryCheck check = DVMemoryCheck.run(<String, Object?>{
      'memory': <String, Object?>{'budget': '4GB'},
      'deviceProfiles': <String, Object?>{
        'box': <String, Object?>{'ram': '1GB'},
      },
    }, const <String>[]);
    expect(check.lines.join('\n'), contains('box'));
    expect(check.lines.join('\n'), contains('platform'));
  });

  test('touchPages on a configured mobile or embedded platform warns with '
      'DV-MEMORY-004', () {
    final DVMemoryCheck check = DVMemoryCheck.run(
      <String, Object?>{
        'memory': <String, Object?>{'touchPages': true},
      },
      const <String>['linux', 'android', 'tizen', 'web'],
    );
    expect(check.ok, isTrue, reason: 'the runtime refuses it; not a failure');
    final List<String> flagged = check.lines
        .where((String l) => l.contains('DV-MEMORY-004'))
        .toList();
    expect(flagged, hasLength(2));
    expect(flagged.join('\n'), contains('android'));
    expect(flagged.join('\n'), contains('tizen'));
  });

  test('a configuration mistake fails the check', () {
    final DVMemoryCheck check = DVMemoryCheck.run(<String, Object?>{
      'memory': <String, Object?>{'segment': '100MB'},
    }, const <String>[]);
    expect(check.ok, isFalse);
    expect(check.lines.join('\n'), contains('power of two'));
  });
}
