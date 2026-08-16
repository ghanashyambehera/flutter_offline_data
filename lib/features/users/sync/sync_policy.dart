import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../core/network/api_exception.dart';

enum SyncErrorClass {
  retryable,
  nonRetryable,
}

class SyncPolicy {
  static const int maxAttempts = 5;

  static SyncErrorClass classify(Object error) {
    if (error is DatabaseException) {
      // Local constraint / SQL errors are not fixed by retrying the HTTP call.
      return SyncErrorClass.nonRetryable;
    }

    if (error is ApiException) {
      final code = error.statusCode;
      if (code == null) {
        return SyncErrorClass.retryable;
      }
      if (code == 408 || code == 429 || code >= 500) {
        return SyncErrorClass.retryable;
      }
      return SyncErrorClass.nonRetryable;
    }

    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
        case DioExceptionType.unknown:
          return SyncErrorClass.retryable;
        default:
          final code = error.response?.statusCode;
          if (code == null) return SyncErrorClass.retryable;
          if (code == 408 || code == 429 || code >= 500) {
            return SyncErrorClass.retryable;
          }
          return SyncErrorClass.nonRetryable;
      }
    }

    return SyncErrorClass.retryable;
  }

  static Duration backoffForAttempt(int attemptCount) {
    final seconds = 1 << attemptCount.clamp(1, 5);
    final capped = seconds > 32 ? 32 : seconds;
    return Duration(seconds: capped);
  }
}
