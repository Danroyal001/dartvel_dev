library dartvel_observability;

class DVLogEntry {
  final String level;
  final String message;
  final DateTime timestamp;

  DVLogEntry(this.level, this.message, {DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();
}

class DVObservability {
  const DVObservability();

  void log(String message, {String level = 'info'}) {}
  void metric(String name, num value, {Map<String, String> tags = const {}}) {}
  void trace(String name, void Function() callback) => callback();
}
