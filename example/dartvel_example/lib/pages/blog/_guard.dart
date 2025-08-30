import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

FutureOr<String?> guard(BuildContext context, GoRouterState state) async {
  // Simple example: block id=0
  final id = state.pathParameters['id'];
  
  if (id == '0') return '/';
  
  return null;
}
