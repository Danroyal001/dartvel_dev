// Light, dark, or whatever the device says.
import 'package:material_ui/material_ui.dart';

import '../dartvel_client/dartvel_client.dart';

class const Appearance([final ThemeMode mode = ThemeMode.system]);

void setAppearance(ThemeMode mode) {
  DV.Theme.setMode(mode);
  DV.global<Appearance>(Appearance(mode));
}
