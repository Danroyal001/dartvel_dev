/// The process facts a native process can report: its memory, its host.
library dartvel.observability.otel_process_io;

import 'dart:io';

/// Resource attributes that describe this process and the machine it is on.
Map<String, Object> dvOtelProcessResource() => <String, Object>{
      'process.pid': pid,
      'process.runtime.name': 'dart',
      'process.runtime.version': Platform.version.split(' ').first,
      'host.name': Platform.localHostname,
      'os.type': Platform.operatingSystem,
    };

/// Memory this process holds now and the most it has held, in bytes. Null
/// where the platform cannot say.
({int current, int peak})? dvOtelProcessMemory() {
  try {
    return (current: ProcessInfo.currentRss, peak: ProcessInfo.maxRss);
  } on Object {
    return null;
  }
}

/// The process environment, for the standard OTEL_* variables.
Map<String, String> dvOtelEnvironment() => Platform.environment;
