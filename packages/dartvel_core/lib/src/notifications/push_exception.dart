/// Thrown when a push service rejects a notification.
library;

class DVPushProviderException implements Exception {
  final String provider;
  final int? statusCode;
  final String message;
  final String? responseBody;

  /// The service's own code for what went wrong, when it gave one: FCM's
  /// `UNREGISTERED`, `QUOTA_EXCEEDED`; Google OAuth's `invalid_grant`.
  final String? errorCode;

  const DVPushProviderException(
    this.provider,
    this.message, {
    this.statusCode,
    this.responseBody,
    this.errorCode,
  });

  /// True when the service says this device token is no longer valid, so the
  /// application should stop sending to it and prune its record.
  bool get isUnregisteredToken {
    if (errorCode != null) {
      return errorCode == 'UNREGISTERED' || errorCode == 'NOT_FOUND';
    }
    if (statusCode == 404) return true;
    final body = responseBody;
    if (body == null) return false;
    return body.contains('UNREGISTERED') || body.contains('NOT_FOUND');
  }

  /// True when sending the same message again later may succeed: the service
  /// is busy or unavailable, not objecting to the message or the credentials.
  bool get isRetryable {
    const retryableCodes = <String>{
      'QUOTA_EXCEEDED',
      'UNAVAILABLE',
      'INTERNAL',
    };
    if (errorCode != null && retryableCodes.contains(errorCode)) return true;
    final status = statusCode;
    return status == 429 || (status != null && status >= 500);
  }

  @override
  String toString() {
    final status = statusCode == null ? '' : ' (HTTP $statusCode)';
    final body = responseBody == null || responseBody!.isEmpty
        ? ''
        : '\nResponse: $responseBody';
    return 'DVPushProviderException[$provider]$status: $message$body';
  }
}
