/// Which values a module call can carry to the backend, and how each is
/// read back from JSON.
///
/// Deliberately small: the types JSON already has, lists and string-keyed
/// maps of them, and bytes. An operation that takes or returns anything
/// else is not carried to the backend; it keeps the outcome the module
/// declares elsewhere, and the README says why.
library;

const Set<String> _scalars = <String>{
  'String', 'int', 'bool', 'num', 'Object', 'dynamic',
};

/// A Dart expression reading a value of [type] out of the JSON [e], or null
/// when [type] cannot cross.
String? dvRpcDecode(String type, String e) {
  final String t = type.replaceAll(' ', '');
  if (t == 'dynamic' || t == 'Object?') return e;
  final bool nullable = t.endsWith('?');
  final String base = nullable ? t.substring(0, t.length - 1) : t;
  if (_scalars.contains(base)) return '($e as $t)';
  if (base == 'double') {
    return nullable ? '($e as num?)?.toDouble()' : '($e as num).toDouble()';
  }
  if (base == 'Uint8List') {
    return nullable
        ? '($e == null ? null : DVModuleRpc.bytes($e))'
        : 'DVModuleRpc.bytes($e)';
  }
  final RegExpMatch? list = RegExp(r'^List<(.+)>$').firstMatch(base);
  if (list != null) {
    final String item = list.group(1)!;
    final String? each = dvRpcDecode(item, 'v');
    if (each == null) return null;
    final String read =
        '<$item>[for (final Object? v in ($e as List<Object?>)) $each]';
    return nullable ? '($e == null ? null : $read)' : read;
  }
  final RegExpMatch? map = RegExp(r'^Map<String,(.+)>$').firstMatch(base);
  if (map != null) {
    final String value = map.group(1)!;
    final String? each = dvRpcDecode(value, 'm.value');
    if (each == null) return null;
    final String read = '<String, $value>{for (final MapEntry<String, Object?> '
        'm in ($e as Map<String, Object?>).entries) m.key: '
        '$each}';
    return nullable ? '($e == null ? null : $read)' : read;
  }
  return null;
}

/// The type a `Future` or `void` return answers with, or null when [returnType]
/// is not something a call to the backend can return: a call over the wire
/// can only answer later.
String? dvRpcAnswerType(String returnType) {
  final String t = returnType.replaceAll(' ', '');
  final RegExpMatch? m = RegExp(r'^Future<(.+)>$').firstMatch(t);
  if (m == null) return null;
  return m.group(1);
}
