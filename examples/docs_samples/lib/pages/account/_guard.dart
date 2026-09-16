// docs:start routing-guard
// lib/pages/account/_guard.dart runs before every page under /account.
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';

FutureOr<String?> guard(BuildContext context, GoRouterState state) {
  // Return a path to redirect there, or null to let the page open.
  if (DV.Auth.currentUser == null) return '/';
  return null;
}
// docs:end
