// GET /api/health
Map<String, dynamic> handler() {
  return {
    'status': 'ok',
    'timestamp': DateTime.now().toIso8601String(),
  };
}
