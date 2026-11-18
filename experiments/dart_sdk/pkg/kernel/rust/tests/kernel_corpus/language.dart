// Closures, exceptions, generators, async, records, patterns, enums,
// mixins, extension types, late fields, generics: what the kernel tree
// carries for each.
import 'dart:async';
import 'dart:collection';

enum Shape { circle, square }

mixin Named {
  String get name;
  String describe() => 'I am $name';
}

abstract class Animal with Named {
  Animal(this.legs);
  final int legs;
}

final class Dog extends Animal {
  Dog() : super(4);
  @override
  String get name => 'dog';
}

extension type Meters(double value) {
  Meters operator +(Meters other) => Meters(value + other.value);
}

extension on int {
  int get doubled => this * 2;
}

class Box<T extends Comparable<T>> {
  Box(this.items);
  final List<T> items;
  late final T largest = items.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
}

Iterable<int> countTo(int n) sync* {
  for (var i = 1; i <= n; i++) {
    yield i;
  }
}

Stream<int> ticks(int n) async* {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
    yield i;
  }
}

(int, {String label}) pair(int x) => (x * x, label: 'square of $x');

String classify(Object? value) => switch (value) {
      null => 'null',
      int n when n < 0 => 'negative',
      int n => 'int $n',
      [var first, ...] => 'list starting with $first',
      {'k': var v} => 'map with $v',
      (int a, String b) => 'record $a $b',
      _ => 'other',
    };

Future<int> divide(int a, int b) async {
  if (b == 0) throw ArgumentError('b is zero');
  return a ~/ b;
}

void main() async {
  var counter = 0;
  final increment = () => ++counter;
  increment();
  increment();
  print('counter $counter');
  print(Dog().describe());
  print(Shape.values.map((s) => s.name).join(','));
  print((Meters(1.5) + Meters(2)).value);
  print(21.doubled);
  print(Box([3, 9, 4]).largest);
  print(countTo(5).toList());
  print(await ticks(3).toList());
  final (square, :label) = pair(7);
  print('$square $label');
  for (final v in [null, -3, 4, [1, 2], {'k': 'v'}, (1, 'b'), 2.5]) {
    print(classify(v));
  }
  try {
    await divide(1, 0);
  } on ArgumentError catch (e, stack) {
    print('caught ${e.message} ${stack.runtimeType != Null}');
  } finally {
    print('finally');
  }
  final queue = Queue<String>()..addAll(['a', 'b']);
  print(queue.removeFirst());
  final completer = Completer<String>();
  scheduleMicrotask(() => completer.complete('microtask'));
  print(await completer.future);
  outer:
  for (var i = 0; i < 3; i++) {
    for (var j = 0; j < 3; j++) {
      if (j == 2) continue outer;
      if (i == 2) break outer;
      print('$i$j');
    }
  }
  switch (counter) {
    case 1:
      print('one');
    case 2:
      print('two');
    default:
      print('many');
  }
}
