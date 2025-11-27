// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

void main() async {
  print('Starting stress test...');
  final client = HttpClient();
  final futures = <Future>[];
  final count = 100;

  for (var i = 0; i < count; i++) {
    futures.add(Future(() async {
      try {
        final req =
            await client.getUrl(Uri.parse('http://127.0.0.1:3000/api/health'));
        final resp = await req.close();
        if (resp.statusCode != 200) {
          print('Request $i failed: ${resp.statusCode}');
        }
      } catch (e) {
        print('Request $i error: $e');
      }
    }));
  }

  await Future.wait(futures);
  print('Stress test complete. If backend is still running, test passed.');
  client.close();
}
