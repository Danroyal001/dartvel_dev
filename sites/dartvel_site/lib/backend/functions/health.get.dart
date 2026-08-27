// GET /api/health
Map<String, Object?> handler() {
  return {
    'status': 'ok',
    'timestamp': DateTime.now().toIso8601String(),
  };
}
