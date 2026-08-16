import 'package:dio/dio.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/network/dio_client.dart';
import '../models/user_dto.dart';

class UserRemoteDataSource {
  UserRemoteDataSource(this._dioClient);

  final DioClient _dioClient;

  /// JSONPlaceholder may not persist data; 2xx + parseable id is success.
  Future<Map<String, dynamic>> createUser({
    required Map<String, dynamic> payload,
    required String localId,
  }) async {
    try {
      final response = await _dioClient.dio.post<Map<String, dynamic>>(
        '/users',
        data: payload,
        options: Options(
          headers: {'X-Client-Request-Id': localId},
        ),
      );

      final data = response.data;
      if (data == null) {
        throw ApiException('Empty response body on create.');
      }

      final serverId = UserDto.parseServerId(data);
      if (serverId == null) {
        throw ApiException('Missing id in create response.');
      }

      return data;
    } on DioException catch (error) {
      throw _mapDioError(error);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException(error.toString());
    }
  }

  Future<Map<String, dynamic>> updateUser({
    required String serverId,
    required Map<String, dynamic> payload,
    required String localId,
  }) async {
    try {
      final response = await _dioClient.dio.put<Map<String, dynamic>>(
        '/users/$serverId',
        data: payload,
        options: Options(
          headers: {'X-Client-Request-Id': localId},
        ),
      );

      final data = response.data;
      if (data == null) {
        throw ApiException('Empty response body on update.');
      }

      return data;
    } on DioException catch (error) {
      throw _mapDioError(error);
    } catch (error) {
      throw ApiException(error.toString());
    }
  }

  ApiException _mapDioError(DioException error) {
    final statusCode = error.response?.statusCode;
    final message = error.response?.data?.toString() ??
        error.message ??
        'Network request failed';
    return ApiException(message, statusCode: statusCode);
  }
}
