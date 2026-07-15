import 'dart:async';

/// Task priority
enum TaskPriority {
  low,
  normal,
  high,
  critical,
}

/// Background task definition
abstract class Task {
  String get id;
  String get name;
  TaskPriority get priority => TaskPriority.normal;
  Future<void> execute(Map<String, dynamic> data);
}

/// Task manager
class TaskManager {
  static final TaskManager _instance = TaskManager._();
  final Map<String, Task> _tasks = {};
  final _queue = StreamController<Map<String, dynamic>>();

  TaskManager._() {
    _queue.stream.listen(_processTask);
  }

  static TaskManager get instance => _instance;

  void register(Task task) {
    _tasks[task.name] = task;
  }

  Future<void> schedule(String taskName, Map<String, dynamic> data,
      {Duration? delay}) async {
    if (delay != null) {
      Timer(delay, () => _queue.add({'name': taskName, 'data': data}));
    } else {
      _queue.add({'name': taskName, 'data': data});
    }
  }

  Future<void> _processTask(Map<String, dynamic> payload) async {
    final name = payload['name'] as String;
    final data = payload['data'] as Map<String, dynamic>;
    final task = _tasks[name];

    if (task != null) {
      try {
        await task.execute(data);
      } catch (e) {
        // ignore: avoid_print
        print('Task $name failed: $e');
      }
    }
  }
}
