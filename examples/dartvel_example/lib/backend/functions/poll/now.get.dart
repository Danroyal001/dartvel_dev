Map<String, Object?> now([String? last]) {
  final ts = DateTime.now().toIso8601String();
  return <String, Object?>{'now': ts, 'changed': last == null || last != ts};
}
