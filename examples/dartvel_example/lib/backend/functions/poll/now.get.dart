Map<String, dynamic> now([String? last]) {
  final ts = DateTime.now().toIso8601String();
  return {'now': ts, 'changed': last == null || last != ts};
}

