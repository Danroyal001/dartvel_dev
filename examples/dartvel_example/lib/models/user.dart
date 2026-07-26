// ignore_for_file: unused_element

import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _User {
  final String name;
  final String email;
  @DVModel.sensitiveField()
  final String recoveryToken;

  const _User({
    required this.name,
    required this.email,
    required this.recoveryToken,
  });
}
