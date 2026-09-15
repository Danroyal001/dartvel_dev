/// Step-up for generated calls: a call the server refused for a missing or
/// stale second factor presents the challenge and is sent again.
///
/// The specification's shape for `@DVBackendFunction(mfa: ...)`: an
/// unsatisfied requirement is not an error page, it suspends the call,
/// presents the generated challenge and resumes, so application code does not
/// handle it. The generated client sends every call through [DVStepUp.send];
/// the generated Flutter runtime installs [DVStepUp.challenge].
///
/// What goes wrong here goes wrong quietly, so each guard says where it is:
///
/// * only the server's `mfa_required` answer is a step-up -- any other 401 is
///   a session that no longer works, and asking it for a code would keep a
///   revoked device looking signed in;
/// * a call is sent again once at most, however the second answer reads;
/// * calls refused together share one challenge rather than stacking five;
/// * a dismissed or failed challenge returns the refusal and sends nothing.
library dartvel_core.auth.step_up;

import 'dart:async';
import 'dart:convert';

import '../http/transport.dart' show DVHttpResponse;

/// What the server asked for.
class DVStepUpRequest {
  const DVStepUpRequest({this.maxAge});

  /// How recent the second factor must be, when the requirement has a
  /// window; null for "at some point in this session".
  final Duration? maxAge;

  @override
  String toString() => 'DVStepUpRequest(maxAge: $maxAge)';
}

/// Presents the second-factor challenge for a refused call, and sends it
/// again.
class DVStepUp {
  const DVStepUp._();

  /// Presents the challenge and answers whether a second factor was
  /// presented. Null presents nothing and the refusal is returned.
  static Future<bool> Function(DVStepUpRequest request)? challenge;

  static Future<bool>? _presenting;

  /// Whether [response] is the server asking for a second factor
  /// (`DV-SESSION-001`) rather than any other refusal.
  static bool isRequired(DVHttpResponse response) {
    if (response.statusCode != 401) return false;
    try {
      final Object? decoded = jsonDecode(response.body);
      return decoded is Map && decoded['error'] == 'mfa_required';
    } on FormatException {
      return false;
    }
  }

  /// Sends [request]; when the answer asks for a second factor, presents the
  /// challenge and, if one was presented, sends it once more.
  static Future<DVHttpResponse> send(
    Future<DVHttpResponse> Function() request,
  ) async {
    final DVHttpResponse first = await request();
    if (!isRequired(first)) return first;
    final Future<bool> Function(DVStepUpRequest)? present = challenge;
    if (present == null) return first;
    Future<bool>? pending = _presenting;
    if (pending == null) {
      final Future<bool> started = _present(present, _requestOf(first));
      pending = started;
      _presenting = started;
      unawaited(started.whenComplete(() {
        if (identical(_presenting, started)) _presenting = null;
      }));
    }
    if (!await pending) return first;
    return request();
  }

  static Future<bool> _present(
    Future<bool> Function(DVStepUpRequest) present,
    DVStepUpRequest request,
  ) async {
    try {
      return await present(request);
    } on Object {
      return false;
    }
  }

  static DVStepUpRequest _requestOf(DVHttpResponse response) {
    try {
      final Object? decoded = jsonDecode(response.body);
      final Object? maxAge = decoded is Map ? decoded['maxAge'] : null;
      return DVStepUpRequest(
          maxAge: maxAge is int ? Duration(seconds: maxAge) : null);
    } on FormatException {
      return const DVStepUpRequest();
    }
  }
}
