// A home widget written as a class, so the class shape is built rather than
// only unit-tested.
//
// The specification puts @DVHomeWidget on "any widget, whether
// Flutter-native, DVClassWidget, or DVFunctionalWidget", and until recently
// only the function shape was read: a class carrying the annotation was
// mistaken for the class it extends, and the developer was told to rename
// StatelessWidget. Nothing about that failed in CI, because no project the
// build ran against had one.
//
// Public, unlike every function-shaped generation input. There is nothing to
// generate from a widget class -- it is already a widget -- so the generated
// route names this class where it lives, and a private one could not be named
// from the router at all.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';

@DVHomeWidget(title: 'Next shift')
class NextShiftWidget extends StatelessWidget {
  const NextShiftWidget({super.key});

  @override
  Widget build(BuildContext context) => const DVBox.list(<Widget>[
        DVText('Tomorrow, 09:00'),
        DVText('Front of house'),
      ]);
}
