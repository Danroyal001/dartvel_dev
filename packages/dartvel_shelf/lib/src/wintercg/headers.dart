import 'dart:collection';

class Headers {
  final Map<String, List<String>> _map = {};
  Headers([Map<String, dynamic>? init]) {
    if (init != null) {
      init.forEach((k, v) {
        if (v is Iterable) {
          for (final vv in v) append(k, vv.toString());
        } else if (v != null) {
          set(k, v.toString());
        }
      });
    }
  }
  static String _norm(String name) => name.toLowerCase();
  void append(String name, String value) {
    final key = _norm(name);
    (_map[key] ??= <String>[]).add(value);
  }

  void set(String name, String value) {
    _map[_norm(name)] = [value];
  }

  bool has(String name) => _map.containsKey(_norm(name));
  String? get(String name) {
    final vals = _map[_norm(name)];
    if (vals == null || vals.isEmpty) return null;
    return vals.first;
  }

  Iterable<String> getAll(String name) =>
      List.unmodifiable(_map[_norm(name)] ?? const []);
  void delete(String name) => _map.remove(_norm(name));
  Map<String, String> get singleValueMap => {
        for (final e in _map.entries)
          e.key: e.value.isEmpty ? '' : e.value.first
      };
  Map<String, List<String>> get multiValueMap => UnmodifiableMapView(_map);
}
