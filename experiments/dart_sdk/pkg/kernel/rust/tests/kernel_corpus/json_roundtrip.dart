import 'dart:convert';

void main() {
  final Map<String, Object?> value = {
    'name': 'kernel',
    'version': 141,
    'tags': ['rust', 'dart', null, true, 1.5],
    'nested': {'a': 1, 'b': [2, 3]},
  };
  final text = jsonEncode(value);
  print(text);
  final decoded = jsonDecode(text) as Map<String, Object?>;
  print(decoded['tags']);
  print(const JsonEncoder.withIndent('  ').convert(decoded['nested']));
}
