// Reading Windows' idea of which serial ports exist.
//
// The FFI around CreateFileW and SetCommState can only be exercised on
// Windows, and only against a device. The parts that decide *what to open*
// and *what to say when it fails* are neither: they are string work, and
// they are where the quiet mistakes live. A port list that silently drops
// COM10 because it sorted as text, or an open failure reported as "error 2",
// are both things a Windows runner would pass over and a person would hit.
import 'package:dartvel_flutter/src/platform/windows/windows_serial_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the port list', () {
    test('is the device names, not the registry keys they are filed under', () {
      // HKLM\HARDWARE\DEVICEMAP\SERIALCOMM maps a driver's own path to the
      // COM name. The value is what a caller opens; the key is not.
      final List<Map<String, Object?>> ports = dvWindowsSerialPorts(
        <String, String>{
          r'\Device\Serial0': 'COM1',
          r'\Device\VCP0': 'COM3',
        },
      );

      expect(ports.map((Map<String, Object?> p) => p['name']),
          <String>['COM1', 'COM3']);
    });

    test('the path is the one CreateFileW needs, not the bare name', () {
      // COM10 and above cannot be opened as "COM10": the Win32 name space
      // needs the \\.\ prefix, and without it every machine with more than
      // nine ports works for the first nine and fails for the rest.
      final List<Map<String, Object?>> ports = dvWindowsSerialPorts(
        <String, String>{r'\Device\Serial9': 'COM10'},
      );

      expect(ports.single['path'], r'\\.\COM10');
    });

    test('COM10 sorts after COM9, not before it', () {
      final List<Map<String, Object?>> ports = dvWindowsSerialPorts(
        <String, String>{
          r'\Device\A': 'COM10',
          r'\Device\B': 'COM9',
          r'\Device\C': 'COM1',
        },
      );

      expect(ports.map((Map<String, Object?> p) => p['name']),
          <String>['COM1', 'COM9', 'COM10']);
    });

    test('a value that is not a COM name is left out', () {
      // The key exists on machines with virtual devices that are not ports.
      // Handing one back produces an open that fails for a reason nobody
      // asked about.
      final List<Map<String, Object?>> ports = dvWindowsSerialPorts(
        <String, String>{r'\Device\Odd': 'NotAPort', r'\Device\S': 'COM2'},
      );

      expect(ports.map((Map<String, Object?> p) => p['name']), <String>['COM2']);
    });

    test('no ports at all is an empty list, not a failure', () {
      // A machine with no serial hardware is the common case on a laptop and
      // on a CI runner, and it is not an error.
      expect(dvWindowsSerialPorts(const <String, String>{}), isEmpty);
    });
  });

  group('what it says when opening fails', () {
    test('a port that is not there says so, by name', () {
      // ERROR_FILE_NOT_FOUND. "error 2" is a number somebody has to look up.
      final String message = dvWindowsSerialFailure(2, 'COM99');

      expect(message, contains('COM99'));
      expect(message.toLowerCase(), contains('not'));
      expect(message, isNot(contains('error 2')));
    });

    test('a port somebody else has open says that, not "not found"', () {
      // ERROR_ACCESS_DENIED, which on a serial port almost always means
      // another program is holding it -- a different problem with a
      // different fix, and the one people actually hit.
      final String message = dvWindowsSerialFailure(5, 'COM3');

      expect(message, contains('COM3'));
      expect(message.toLowerCase(), contains('another'));
    });

    test('a code it does not recognise still names the port and the code', () {
      final String message = dvWindowsSerialFailure(1234, 'COM4');

      expect(message, contains('COM4'));
      expect(message, contains('1234'));
    });
  });
}
