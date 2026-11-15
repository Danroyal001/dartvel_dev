int fib(int n) => n < 2 ? n : fib(n - 1) + fib(n - 2);

String fizz(int i) {
  if (i % 15 == 0) return 'FizzBuzz';
  if (i % 5 == 0) return 'Buzz';
  if (i % 3 == 0) return 'Fizz';
  return '$i';
}

void main() {
  final out = <String>[];
  for (var i = 1; i <= 15; i++) {
    out.add(fizz(i));
  }
  print(out.join(' '));
  print('fib(25) = ${fib(25)}');
  var n = 27;
  var steps = 0;
  while (n != 1) {
    n = n.isEven ? n ~/ 2 : 3 * n + 1;
    steps++;
  }
  print('collatz(27) takes $steps steps');
  final counts = <String, int>{};
  for (final word in 'the cat and the hat and the bat'.split(' ')) {
    counts[word] = (counts[word] ?? 0) + 1;
  }
  print(counts);
  final keys = counts.keys.toList();
  print('${keys.length} distinct, first ${keys.first}, last ${keys.last}');
  print([1, 2, 3].contains(2) && !<int>[].contains(1));
  print(int.parse('-9001') + 1);
  print('${9223372036854775807 + 1}');
  var label = '';
  for (var i = 0; i < 10; i++) {
    if (i == 3) continue;
    if (i == 7) break;
    label += '$i';
  }
  print(label);
}
