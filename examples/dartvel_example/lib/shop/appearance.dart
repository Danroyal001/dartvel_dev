// Light, dark, or whatever the device says.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';

class Appearance {
  const Appearance([this.mode = ThemeMode.system]);

  final ThemeMode mode;
}

void setAppearance(ThemeMode mode) {
  DV.Theme.setMode(mode);
  DV.global<Appearance>(Appearance(mode));
}
