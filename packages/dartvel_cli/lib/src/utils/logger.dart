import 'dart:io';

void log(String message) => stdout.writeln('[dartvel] $message');

class Logger {
  static void log(String message, {bool isError = false}) {
    if (isError) {
      stderr.writeln('[dartvel] $message');
    } else {
      stdout.writeln('[dartvel] $message');
    }
  }

  static void error(String message) => log(message, isError: true);
}
