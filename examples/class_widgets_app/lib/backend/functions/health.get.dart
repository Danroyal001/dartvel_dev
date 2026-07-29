// GET /api/health
Map<String, Object?> handler() {
  return <String, Object?>{
    'status': 'ok',
    'timestamp': DateTime.now().toIso8601String(),
  };
}
