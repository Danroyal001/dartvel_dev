import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartvel_core/dartvel.dart';

class RouteGenerator extends GeneratorForAnnotation<Route> {
  @override
  String generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        'Generator cannot target `${element.name}`.',
        todo: 'Remove the Route annotation from `${element.name}`.',
        element: element,
      );
    }

    final path = annotation.read('path').stringValue;
    final name = annotation.read('name').isNull ? null : annotation.read('name').stringValue;
    
    // Simple generation logic for now
    return '// Route: $path (name: $name) for class ${element.name}';
  }
}

Builder routeBuilder(BuilderOptions options) =>
    SharedPartBuilder([RouteGenerator()], 'route_generator');
