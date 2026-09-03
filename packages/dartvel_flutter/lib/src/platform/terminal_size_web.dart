import 'terminal_size.dart';

/// No terminal in a browser.
DVTerminalSize dvReadAttachedTerminalSize() => const DVTerminalSize(columns: 80, rows: 24);

Stream<void> dvTerminalWindowChanges() => const Stream<void>.empty();

bool dvDisplayAvailable() => true;
