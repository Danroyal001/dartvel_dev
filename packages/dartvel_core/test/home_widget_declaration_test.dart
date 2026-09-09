// What a `@DVHomeWidget` may sit above.
//
// The specification puts the annotation "on any widget, whether
// Flutter-native, `DVClassWidget`, or `DVFunctionalWidget`". Only the
// function shape was ever read. A class carried the annotation and got a
// message about `StatelessWidget`, because the pattern's return-type
// alternative swallowed `class _StepCounter extends` and then took the
// superclass for the declared name -- so the developer was told to rename a
// class in the Flutter SDK, and the widget they wrote was never seen.
//
// One pattern in core, because two scanners read it: the generator that
// writes the route, and the build check that decides whether the target has
// anywhere to put a widget. They held a copy each once, and a build that
// reports one set of widgets and packages another is what that cost.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

RegExpMatch _match(String source) {
  final Iterable<RegExpMatch> all = dvHomeWidgetDeclaration.allMatches(source);
  expect(all, hasLength(1), reason: 'no single declaration was found');
  return all.first;
}

void main() {
  test('a functional widget declares the function it sits above', () {
    final RegExpMatch match = _match('''
@DVHomeWidget()
@DVFunctionalWidget()
Widget _stepCounterWidget(BuildContext context) => const Text('1,204');
''');

    expect(dvHomeWidgetDeclaredName(match), '_stepCounterWidget');
    expect(dvHomeWidgetIsClass(match), isFalse);
    expect(dvHomeWidgetAnnotationArgs(match), '');
  });

  test('a widget class declares the class, not what it extends', () {
    // The whole of the old bug in one assertion. `StatelessWidget` came back
    // here, and every later step -- the privacy check, the identifier, the
    // route, the provider -- was working on the wrong name.
    final RegExpMatch match = _match('''
@DVHomeWidget(title: 'Steps today')
class StepCounterWidget extends StatelessWidget {
  const StepCounterWidget({super.key});

  @override
  Widget build(BuildContext context) => const Text('1,204');
}
''');

    expect(dvHomeWidgetDeclaredName(match), 'StepCounterWidget');
    expect(dvHomeWidgetIsClass(match), isTrue);
    expect(dvHomeWidgetAnnotationArgs(match), "title: 'Steps today'");
  });

  test('a DVClassWidget is a widget class like any other', () {
    // The specification names this shape outright, and it is the one whose
    // superclass is a Dartvel type -- so a pattern that read the superclass
    // would have produced `DVClassWidget` as the widget's own name, and an
    // identifier of `dvclass`, on every one of them.
    final RegExpMatch match = _match('''
@DVHomeWidget()
class NextShiftWidget extends DVClassWidget {
  const NextShiftWidget({super.key});
}
''');

    expect(dvHomeWidgetDeclaredName(match), 'NextShiftWidget');
    expect(dvHomeWidgetIsClass(match), isTrue);
  });

  test('a widget class with no superclass is still a widget class', () {
    final RegExpMatch match = _match('''
@DVHomeWidget()
class NextShiftWidget {}
''');

    expect(dvHomeWidgetDeclaredName(match), 'NextShiftWidget');
    expect(dvHomeWidgetIsClass(match), isTrue);
  });
}
