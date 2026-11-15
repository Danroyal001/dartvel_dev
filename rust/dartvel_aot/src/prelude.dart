// The core library dartvel_aot compiles with every program (not a ported
// file). It is ordinary Dart in the subset the compiler accepts, so the
// tree shaker treats it exactly like user code: whatever a program cannot
// reach, from `jsonDecode` to a class's `toString`, is not in its binary.
//
// `external` functions are implemented in C by the back end (natives.rs).
// The built-in classes (Object, Null, bool, int, String, List, Map) hold
// no Dart fields: their values are made by the runtime.

external void _printString(String text);
external Never _throw(String message);
external String _className(Object object);
external String _intToString(int value);
external int _strLen(String text);
external String _strSub(String text, int start, int end);
external int _strIndexOf(String text, String pattern, int start);
external int _strCodeUnitAt(String text, int index);
external String _strFromCharCode(int code);
external String _strTrim(String text);
external String _strLower(String text);
external String _strUpper(String text);
external String _strJoin(List parts, String separator);
external int _listLen(List list);
external void _listAdd(List list, Object? value);
external Object? _listGet(List list, int index);
external void _listSet(List list, int index, Object? value);
external Object? _listRemoveLast(List list);
external Object? _mapGet(Map map, Object? key);
external void _mapSet(Map map, Object? key, Object? value);
external bool _mapContainsKey(Map map, Object? key);
external int _mapLen(Map map);
external List _mapKeyList(Map map);
external Object? _mapRemove(Map map, Object? key);

void print(Object? object) {
  _printString('$object');
}

class Object {
  String toString() => "Instance of '${_className(this)}'";
}

class Null {
  String toString() => 'null';
}

class bool {
  String toString() => this ? 'true' : 'false';
}

class int {
  String toString() => _intToString(this);
  bool get isEven => this % 2 == 0;
  bool get isOdd => this % 2 != 0;

  static int parse(String source) {
    final length = _strLen(source);
    var index = 0;
    var negative = false;
    if (length > 0 && (_strCodeUnitAt(source, 0) == 45 || _strCodeUnitAt(source, 0) == 43)) {
      negative = _strCodeUnitAt(source, 0) == 45;
      index = 1;
    }
    if (index >= length) {
      _throw('FormatException: Invalid radix-10 number (at character 1)\n$source\n^\n');
    }
    var value = 0;
    while (index < length) {
      final digit = _strCodeUnitAt(source, index) - 48;
      if (digit < 0 || digit > 9) {
        _throw('FormatException: Invalid radix-10 number (at character 1)\n$source\n^\n');
      }
      value = value * 10 - digit;
      index++;
    }
    return negative ? value : -value;
  }
}

class String {
  String toString() => this;
  int get length => _strLen(this);
  bool get isEmpty => _strLen(this) == 0;
  bool get isNotEmpty => _strLen(this) != 0;
  String operator [](int index) => _strSub(this, index, index + 1);
  int codeUnitAt(int index) => _strCodeUnitAt(this, index);
  String substring(int start, [int? end]) => _strSub(this, start, end ?? _strLen(this));
  int indexOf(String pattern) => _strIndexOf(this, pattern, 0);
  bool contains(String other) => _strIndexOf(this, other, 0) >= 0;
  bool startsWith(String prefix) =>
      _strLen(prefix) <= _strLen(this) && _strSub(this, 0, _strLen(prefix)) == prefix;
  bool endsWith(String suffix) =>
      _strLen(suffix) <= _strLen(this) &&
      _strSub(this, _strLen(this) - _strLen(suffix), _strLen(this)) == suffix;
  String trim() => _strTrim(this);
  String toLowerCase() => _strLower(this);
  String toUpperCase() => _strUpper(this);

  List<String> split(String separator) {
    final parts = <String>[];
    if (_strLen(separator) == 0) {
      for (var i = 0; i < _strLen(this); i++) {
        parts.add(_strSub(this, i, i + 1));
      }
      return parts;
    }
    var start = 0;
    var found = _strIndexOf(this, separator, 0);
    while (found >= 0) {
      parts.add(_strSub(this, start, found));
      start = found + _strLen(separator);
      found = _strIndexOf(this, separator, start);
    }
    parts.add(_strSub(this, start, _strLen(this)));
    return parts;
  }

  static String fromCharCode(int code) => _strFromCharCode(code);
}

class List {
  int get length => _listLen(this);
  bool get isEmpty => _listLen(this) == 0;
  bool get isNotEmpty => _listLen(this) != 0;
  Object? operator [](int index) => _listGet(this, index);
  void operator []=(int index, Object? value) {
    _listSet(this, index, value);
  }

  void add(Object? value) {
    _listAdd(this, value);
  }

  Object? removeLast() => _listRemoveLast(this);

  Object? get first {
    if (_listLen(this) == 0) _throw('Bad state: No element');
    return _listGet(this, 0);
  }

  Object? get last {
    if (_listLen(this) == 0) _throw('Bad state: No element');
    return _listGet(this, _listLen(this) - 1);
  }

  bool contains(Object? element) {
    for (var i = 0; i < _listLen(this); i++) {
      if (_listGet(this, i) == element) return true;
    }
    return false;
  }

  String join([String separator = '']) {
    final parts = <String>[];
    for (var i = 0; i < _listLen(this); i++) {
      parts.add('${_listGet(this, i)}');
    }
    return _strJoin(parts, separator);
  }

  List toList() {
    final copy = [];
    for (var i = 0; i < _listLen(this); i++) {
      copy.add(_listGet(this, i));
    }
    return copy;
  }

  _ListIterator get iterator => _ListIterator(this);

  String toString() => '[${join(', ')}]';
}

class _ListIterator {
  final List _list;
  int _index = -1;
  _ListIterator(this._list);

  bool moveNext() {
    _index++;
    return _index < _listLen(_list);
  }

  Object? get current => _listGet(_list, _index);
}

class Map {
  Object? operator [](Object? key) => _mapGet(this, key);
  void operator []=(Object? key, Object? value) {
    _mapSet(this, key, value);
  }

  int get length => _mapLen(this);
  bool get isEmpty => _mapLen(this) == 0;
  bool get isNotEmpty => _mapLen(this) != 0;
  bool containsKey(Object? key) => _mapContainsKey(this, key);
  Object? remove(Object? key) => _mapRemove(this, key);
  _MapKeys get keys => _MapKeys(this);

  List get values {
    final result = [];
    final keyList = _mapKeyList(this);
    for (var i = 0; i < _listLen(keyList); i++) {
      result.add(_mapGet(this, _listGet(keyList, i)));
    }
    return result;
  }

  String toString() {
    final parts = <String>[];
    final keyList = _mapKeyList(this);
    for (var i = 0; i < _listLen(keyList); i++) {
      final key = _listGet(keyList, i);
      parts.add('$key: ${_mapGet(this, key)}');
    }
    return '{${_strJoin(parts, ', ')}}';
  }
}

class _MapKeys {
  final Map _map;
  _MapKeys(this._map);

  int get length => _mapLen(_map);
  _ListIterator get iterator => _ListIterator(_mapKeyList(_map));
  List toList() => _mapKeyList(_map);
  Object? get first => _mapKeyList(_map).first;
  Object? get last => _mapKeyList(_map).last;
  bool contains(Object? key) => _mapContainsKey(_map, key);
  String toString() => '(${_mapKeyList(_map).join(', ')})';
}

class StringBuffer {
  final List _parts = [];
  StringBuffer();

  void write(Object? object) {
    _parts.add('$object');
  }

  int get length => _strLen(_strJoin(_parts, ''));
  String toString() => _strJoin(_parts, '');
}

String jsonEncode(Object? value) {
  final out = <String>[];
  _jsonWrite(value, out);
  return _strJoin(out, '');
}

void _jsonWrite(Object? value, List out) {
  if (value == null) {
    out.add('null');
  } else if (value is bool) {
    out.add(value ? 'true' : 'false');
  } else if (value is int) {
    out.add(_intToString(value));
  } else if (value is String) {
    _jsonWriteString(value, out);
  } else if (value is List) {
    out.add('[');
    for (var i = 0; i < _listLen(value); i++) {
      if (i > 0) out.add(',');
      _jsonWrite(_listGet(value, i), out);
    }
    out.add(']');
  } else if (value is Map) {
    out.add('{');
    final keyList = _mapKeyList(value);
    for (var i = 0; i < _listLen(keyList); i++) {
      if (i > 0) out.add(',');
      final key = _listGet(keyList, i);
      if (key is! String) {
        _throw('Converting object to an encodable object failed: $value');
      }
      _jsonWriteString(key, out);
      out.add(':');
      _jsonWrite(_mapGet(value, key), out);
    }
    out.add('}');
  } else {
    _throw('Converting object to an encodable object failed: $value');
  }
}

void _jsonWriteString(String text, List out) {
  out.add('"');
  var start = 0;
  final length = _strLen(text);
  for (var i = 0; i < length; i++) {
    final unit = _strCodeUnitAt(text, i);
    if (unit < 32 || unit == 34 || unit == 92) {
      out.add(_strSub(text, start, i));
      start = i + 1;
      if (unit == 34) {
        out.add('\\"');
      } else if (unit == 92) {
        out.add('\\\\');
      } else if (unit == 8) {
        out.add('\\b');
      } else if (unit == 9) {
        out.add('\\t');
      } else if (unit == 10) {
        out.add('\\n');
      } else if (unit == 12) {
        out.add('\\f');
      } else if (unit == 13) {
        out.add('\\r');
      } else {
        out.add('\\u00');
        out.add(_strSub('0123456789abcdef', unit ~/ 16, unit ~/ 16 + 1));
        out.add(_strSub('0123456789abcdef', unit % 16, unit % 16 + 1));
      }
    }
  }
  out.add(_strSub(text, start, length));
  out.add('"');
}

Object? jsonDecode(String source) {
  final parser = _JsonParser(source);
  parser.skipSpace();
  final value = parser.parseValue();
  parser.skipSpace();
  if (parser.index != _strLen(source)) parser.fail();
  return value;
}

class _JsonParser {
  final String source;
  int index = 0;
  _JsonParser(this.source);

  Never fail() {
    _throw('FormatException: Unexpected character (at character ${index + 1})');
  }

  int peek() => index < _strLen(source) ? _strCodeUnitAt(source, index) : -1;

  void skipSpace() {
    while (true) {
      final unit = peek();
      if (unit == 32 || unit == 9 || unit == 10 || unit == 13) {
        index++;
      } else {
        return;
      }
    }
  }

  void expect(String word) {
    if (index + _strLen(word) > _strLen(source) ||
        _strSub(source, index, index + _strLen(word)) != word) {
      fail();
    }
    index += _strLen(word);
  }

  Object? parseValue() {
    final unit = peek();
    if (unit == 123) return parseObject();
    if (unit == 91) return parseArray();
    if (unit == 34) return parseString();
    if (unit == 116) {
      expect('true');
      return true;
    }
    if (unit == 102) {
      expect('false');
      return false;
    }
    if (unit == 110) {
      expect('null');
      return null;
    }
    if (unit == 45 || (unit >= 48 && unit <= 57)) return parseNumber();
    fail();
  }

  Map parseObject() {
    final result = <String, Object?>{};
    index++;
    skipSpace();
    if (peek() == 125) {
      index++;
      return result;
    }
    while (true) {
      skipSpace();
      if (peek() != 34) fail();
      final key = parseString();
      skipSpace();
      if (peek() != 58) fail();
      index++;
      skipSpace();
      result[key] = parseValue();
      skipSpace();
      final unit = peek();
      index++;
      if (unit == 125) return result;
      if (unit != 44) {
        index--;
        fail();
      }
    }
  }

  List parseArray() {
    final result = [];
    index++;
    skipSpace();
    if (peek() == 93) {
      index++;
      return result;
    }
    while (true) {
      skipSpace();
      result.add(parseValue());
      skipSpace();
      final unit = peek();
      index++;
      if (unit == 93) return result;
      if (unit != 44) {
        index--;
        fail();
      }
    }
  }

  String parseString() {
    index++;
    final parts = <String>[];
    var start = index;
    while (true) {
      final unit = peek();
      if (unit < 0) fail();
      if (unit == 34) {
        parts.add(_strSub(source, start, index));
        index++;
        return _strJoin(parts, '');
      }
      if (unit == 92) {
        parts.add(_strSub(source, start, index));
        index++;
        final escape = peek();
        index++;
        if (escape == 34) {
          parts.add('"');
        } else if (escape == 92) {
          parts.add('\\');
        } else if (escape == 47) {
          parts.add('/');
        } else if (escape == 98) {
          parts.add(_strFromCharCode(8));
        } else if (escape == 102) {
          parts.add(_strFromCharCode(12));
        } else if (escape == 110) {
          parts.add('\n');
        } else if (escape == 114) {
          parts.add('\r');
        } else if (escape == 116) {
          parts.add('\t');
        } else if (escape == 117) {
          var code = 0;
          for (var i = 0; i < 4; i++) {
            final digit = peek();
            index++;
            if (digit >= 48 && digit <= 57) {
              code = code * 16 + digit - 48;
            } else if (digit >= 97 && digit <= 102) {
              code = code * 16 + digit - 87;
            } else if (digit >= 65 && digit <= 70) {
              code = code * 16 + digit - 55;
            } else {
              index--;
              fail();
            }
          }
          parts.add(_strFromCharCode(code));
        } else {
          index--;
          fail();
        }
        start = index;
      } else if (unit < 32) {
        fail();
      } else {
        index++;
      }
    }
  }

  int parseNumber() {
    final start = index;
    if (peek() == 45) index++;
    if (peek() < 48 || peek() > 57) fail();
    while (peek() >= 48 && peek() <= 57) {
      index++;
    }
    final unit = peek();
    if (unit == 46 || unit == 101 || unit == 69) {
      _throw('Unsupported: dartvel_aot has no double yet');
    }
    return int.parse(_strSub(source, start, index));
  }
}
