/// Off the web there is no server-rendered document to take over from, and
/// the pressed state is Flutter's own.
library;

import 'password_reveal.dart' show DVServerFieldState;

DVServerFieldState? dvReadServerField(String label) => null;

void dvSetPressed(String identifier, bool pressed) {}

void dvForgetPressed(String identifier) {}
