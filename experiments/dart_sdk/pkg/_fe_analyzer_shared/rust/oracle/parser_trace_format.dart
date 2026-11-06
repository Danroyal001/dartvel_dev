// How the parser oracle writes listener arguments (see ../README.md).
//
// A token is `TYPE@offset"lexeme"`, followed by `~` when it is synthetic; an
// error token is `!errorCode@offset`; a message is `Code"problem"` followed
// by `"correction"` when there is one; null is `-`. Strings are escaped as
// the scanner oracle escapes lexemes, so a trace is pure ASCII.

import 'package:_fe_analyzer_shared/src/messages/codes.dart';
import 'package:_fe_analyzer_shared/src/scanner/error_token.dart';
import 'package:_fe_analyzer_shared/src/scanner/token.dart';

import 'scanner_dump.dart' show escape;

String formatToken(Token? token) {
  if (token == null) return '-';
  if (token is ErrorToken) {
    return '!${token.errorCode.name}@${token.offset}';
  }
  String synthetic = token.isSynthetic ? '~' : '';
  return '${token.type.name}@${token.offset}"${escape(token.lexeme)}"'
      '$synthetic';
}

String formatString(String? value) {
  if (value == null) return '-';
  return '"${escape(value)}"';
}

String formatMessage(Message? message) {
  if (message == null) return '-';
  String? correction = message.correctionMessage;
  return '${message.code.name}"${escape(message.problemMessage)}"'
      '${correction == null ? '' : '"${escape(correction)}"'}';
}
