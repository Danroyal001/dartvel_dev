/// A backend function saying no, and the client hearing it.
///
/// A function that throws is a server error: the generated route answers 500
/// with nothing in it, because an exception's text can name a table, a path or
/// a key. That left a function no way to turn a request down with a reason the
/// reader could be shown -- "That looks like an Ethereum address" became
/// "Internal Server Error". [DVRefusal] is that reason. [DVBackendFunctionException]
/// is the client's half: a generated client function throws it for any answer
/// that is not a success, instead of returning the error text as its result.
library;

import 'dart:convert';

import 'transport.dart';

/// Thrown by a backend function to refuse the request with a reason.
///
/// The generated route answers with [status] and `{"error": message}`, and the
/// generated client throws a [DVBackendFunctionException] carrying both, so
/// the page can show [message] as it stands. Write it for the reader:
///
/// ```dart
/// if (!address.startsWith('T')) {
///   throw const DVRefusal('That looks like an Ethereum address. Paste a TRON (TRC-20) one.');
/// }
/// ```
///
/// [status] is a refusal status, 400 to 499: 422 (the default) for input the
/// function cannot accept, 409 for a conflict such as a name already taken,
/// 404 for something that is not there, 403 for something the caller may not
/// do. Anything else a function throws stays a 500 that shows nothing.
class DVRefusal implements Exception {
  /// Const, so `throw const DVRefusal('...')` works. A status outside 400 to
  /// 499 fails an assert while developing, and the route answers it as 422.
  const DVRefusal(this.message, {this.status = 422})
      : assert(status >= 400 && status <= 499,
            'a refusal status is 400 to 499; a server error is a thrown exception, not a refusal');

  /// What the reader is shown.
  final String message;

  /// The status asked for.
  final int status;

  /// The HTTP status the route answers with: [status], or 422 when [status]
  /// is not a refusal status.
  int get responseStatus => status >= 400 && status <= 499 ? status : 422;

  /// The JSON body the route sends: `{"error": message}`.
  String get responseBody => jsonEncode(<String, String>{'error': message});

  @override
  String toString() => 'DVRefusal($status): $message';
}

/// A generated client function's call that the server refused or failed.
///
/// Thrown for every answer that is not a 2xx, so a failure is never handed
/// back as if it were the function's result. [message] is the server's own
/// `error` text when it sent one (a [DVRefusal] always does), otherwise the
/// body, otherwise a short description of the status.
class DVBackendFunctionException implements Exception {
  const DVBackendFunctionException(this.statusCode, this.message);

  /// The HTTP status the server answered with.
  final int statusCode;

  /// The reason, ready to show the reader when the server refused on purpose.
  final String message;

  /// True when the server turned the request down on purpose (4xx); false
  /// when it failed (5xx and anything else).
  bool get isRefusal => statusCode >= 400 && statusCode < 500;

  /// Throws unless [response] is a success. Called by every generated typed
  /// client function before it decodes the answer.
  static void throwUnlessSuccess(DVHttpResponse response) {
    if (response.isSuccess) return;
    throw DVBackendFunctionException(response.statusCode, _messageOf(response));
  }

  static String _messageOf(DVHttpResponse response) {
    final Object? data = response.data;
    if (data is Map && data['error'] is String && (data['error'] as String).isNotEmpty) {
      return data['error'] as String;
    }
    final String text = response.body.trim();
    if (text.isNotEmpty && text.length <= 300 && !text.startsWith('<')) return text;
    return 'The request failed (HTTP ${response.statusCode}).';
  }

  @override
  String toString() => 'DVBackendFunctionException($statusCode): $message';
}
