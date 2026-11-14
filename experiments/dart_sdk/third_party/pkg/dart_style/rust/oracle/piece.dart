// Oracle for State and Shape in lib/src/piece/piece.dart.
import '../../lib/src/piece/piece.dart';

void main() {
  var states = [
    State.unsplit, State.split,
    State(0, cost: 0), State(255),
    const State(1), const State(1), State(1), State(1),
    const State(1, cost: 4), const State(1, cost: 4),
    const State(0, cost: 0), const State(255),
    for (var n in [-500, -1, 0, 1, 254, 255, 256, 1000000])
      State(n, cost: -n),
  ];
  for (var i = 0; i < states.length; i++) {
    var a = states[i];
    print('state:$i:$a:${a.cost}');
    for (var j = 0; j < states.length; j++) {
      print('pair:$i:$j:${a.compareTo(states[j])}:${a == states[j]}');
    }
  }
  for (var a in Shape.values) {
    for (var b in Shape.values) {
      print('merge:${a.name}:${b.name}:${a.merge(b).name}');
    }
  }
  for (var shapes in [Shape.all, Shape.onlyBlock, Shape.onlyInline,
      Shape.inlineOrBlock, Shape.anyIf(false), Shape.anyIf(true)]) {
    print('set:${shapes.map((s) => s.name).join(',')}');
  }
}
