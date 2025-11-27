import 'package:test/test.dart';
import 'package:dartvel_core/dartvel_core.dart';
import 'package:dartvel_core/src/cache/cache.dart';
import 'package:dartvel_core/src/tasks/background_tasks.dart';

void main() {
  group('Cache Tests', () {
    late Cache cache;

    setUp(() {
      cache = InMemoryCache();
    });

    test('set and get value', () async {
      await cache.set('key', 'value');
      expect(await cache.get('key'), equals('value'));
    });

    test('ttl expiration', () async {
      await cache.set('key', 'value', ttl: Duration(milliseconds: 100));
      expect(await cache.get('key'), equals('value'));
      await Future.delayed(Duration(milliseconds: 150));
      expect(await cache.get('key'), isNull);
    });
  });

  group('TaskManager Tests', () {
    test('task execution', () async {
      final manager = TaskManager.instance;
      bool executed = false;

      final task = _TestTask('test_task', () {
        executed = true;
      });

      manager.register(task);
      await manager.schedule('test_task', {});

      // Allow event loop to process
      await Future.delayed(Duration(milliseconds: 50));

      expect(executed, isTrue);
    });
  });
}

class _TestTask implements Task {
  final String _name;
  final Function _callback;

  _TestTask(this._name, this._callback);

  @override
  String get id => _name;

  @override
  String get name => _name;

  @override
  Future<void> execute(Map<String, dynamic> data) async {
    _callback();
  }
}
