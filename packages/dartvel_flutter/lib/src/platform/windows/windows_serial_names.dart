/// Which serial ports Windows says it has, and what to say when one will not
/// open.
///
/// Separate from the FFI because these are the parts that can be wrong
/// quietly. A port list that drops COM10 because it sorted as text works on
/// every machine with nine ports or fewer; an open failure reported as
/// "error 2" is a number somebody has to go and look up. Neither throws,
/// neither shows on a runner with no serial hardware, and both are string
/// work that a test on any platform can hold to account.
library dartvel_flutter.platform.windows.serial_names;

/// A COM name, and nothing else. `SERIALCOMM` carries virtual devices that
/// are not ports on some machines.
final RegExp _comName = RegExp(r'^COM(\d+)$');

/// The ports named by `HKLM\HARDWARE\DEVICEMAP\SERIALCOMM`.
///
/// [values] maps each driver's own device path to the COM name it answers
/// as. The value is what a caller opens; the key is the driver's business.
List<Map<String, Object?>> dvWindowsSerialPorts(Map<String, String> values) {
  final List<String> names = <String>[
    for (final String value in values.values)
      if (_comName.hasMatch(value.trim())) value.trim(),
  ];

  // By number, not by text. COM10 sorts before COM9 as a string, and a list
  // in that order is not wrong in a way anybody notices until they read it.
  names.sort((String a, String b) => int.parse(_comName.firstMatch(a)!.group(1)!)
      .compareTo(int.parse(_comName.firstMatch(b)!.group(1)!)));

  return <Map<String, Object?>>[
    for (final String name in names)
      <String, Object?>{'name': name, 'path': dvWindowsSerialPath(name)},
  ];
}

/// The path `CreateFileW` needs for [name].
///
/// COM1 through COM9 open under their own names; COM10 and above do not,
/// because they are not in the legacy DOS device name space. The `\\.\`
/// prefix is legal for all of them, so it is used for all of them: a rule
/// with an exception at nine is a bug waiting for somebody's tenth adapter.
String dvWindowsSerialPath(String name) => r'\\.\' + name;

/// What to say when [port] will not open, given a Win32 error code.
///
/// The two that matter are told apart, because they have different fixes and
/// the second is the one people actually hit: a port that is not there, and
/// a port another program is holding.
String dvWindowsSerialFailure(int code, String port) {
  switch (code) {
    case 2: // ERROR_FILE_NOT_FOUND
    case 3: // ERROR_PATH_NOT_FOUND
      return '$port is not a port on this machine. Check the name against '
          'device.serial.ports, and check the adapter is plugged in.';
    case 5: // ERROR_ACCESS_DENIED
      return '$port is open in another program. A serial port is exclusive, '
          'so close whatever is holding it and try again.';
    case 32: // ERROR_SHARING_VIOLATION
      return '$port is in use. Something else has the port open.';
    default:
      return 'Windows would not open $port (error $code).';
  }
}
