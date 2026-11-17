/// Off the web there is no browser history to restore from: a page under a
/// pushed route stays mounted and keeps its own scroll position, and there
/// is no server-rendered document to take over from.
library;

/// Starts listening for back and forward. Nothing to do here.
void dvPageHistoryInstall() {}

/// The address a back or forward just went to, once, or null.
String? dvTakeHistoryNavigation() => null;

/// The browser's key for the history entry on screen, or null.
Object? dvHistoryEntryKey() => null;

/// How far the document was scrolled before the app took over, once.
double dvTakeTakeoverScroll() => 0;

/// Whether the main pointer is a finger. Off the web the platform says so.
bool dvPrimaryPointerIsTouch() => false;
