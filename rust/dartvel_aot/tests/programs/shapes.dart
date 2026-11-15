abstract class Shape {
  String get name;
  int area();
  String describe() => '$name with area ${area()}';
}

class Rect extends Shape {
  final int width;
  final int height;
  Rect(this.width, this.height);

  @override
  String get name => 'rect';

  @override
  int area() => width * height;
}

class Square extends Rect {
  Square(int side) : super(side, side);

  @override
  String get name => 'square';
}

class Triangle extends Shape {
  final int base;
  final int height;
  Triangle(this.base, this.height);

  @override
  String get name => 'triangle';

  @override
  int area() => base * height ~/ 2;

  @override
  String toString() => 'Triangle($base, $height)';
}

class Unused extends Shape {
  @override
  String get name => 'never made';

  @override
  int area() => 0;
}

class Point {
  int x;
  int y;
  Point(this.x, this.y);
}

void main() {
  final shapes = <Shape>[Rect(3, 4), Square(5), Triangle(6, 7)];
  var sum = 0;
  for (final shape in shapes) {
    print(shape.describe());
    sum += shape.area();
  }
  print('sum $sum');
  for (final shape in shapes) {
    print('${shape is Rect} ${shape is Square} ${shape is Triangle}');
  }
  print(shapes[2]);
  print(Point(1, 2));
  final point = Point(1, 2);
  point.x += 10;
  point.y = point.y * -3;
  print('${point.x},${point.y}');
  print('${-7 % 3} ${7 % -3} ${-7 ~/ 2} ${7 ~/ 2} ${1 << 40} ${255 & 15 | 64 ^ 3}');
}
