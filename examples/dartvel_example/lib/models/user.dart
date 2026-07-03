import 'package:dartvel_core/dartvel.dart';

@DVModel()
class User {
  final String name;
  final String email;

  const User({required this.name, required this.email});
}
