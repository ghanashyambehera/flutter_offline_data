import 'dart:developer' as developer;

import '../../../../core/connectivity/connectivity_service.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_change_bus.dart';
import '../data/datasources/user_local_datasource.dart';
import '../data/datasources/user_remote_datasource.dart';
import '../data/models/sync_queue_item.dart';
import '../data/models/user_dto.dart';
import 'sync_policy.dart';

class SyncEngine {
  SyncEngine({
    required UserLocalDataSource localDataSource,
    required UserRemoteDataSource remoteDataSource,
    required ConnectivityService connectivityService,
    required DatabaseChangeBus changeBus,
  })  : _local = localDataSource,
        _remote = remoteDataSource,
        _connectivity = connectivityService,
        _changeBus = changeBus;

  final UserLocalDataSource _local;
  final UserRemoteDataSource _remote;
  final ConnectivityService _connectivity;
  final DatabaseChangeBus _changeBus;

  bool _running = false;

  Future<void> trySync() async {
    if (!_connectivity.isOnline || _running) {
      return;
    }

    _running = true;
    developer.log('sync_started', name: 'SyncEngine');

    try {
      final db = await AppDatabase.instance;
      await AppDatabase.resetInProgressQueue(db);

      var pass = 0;
      while (_connectivity.isOnline && pass < 50) {
        pass++;
        final processed = await _drainPendingQueue();
        if (!processed) break;
      }
    } finally {
      _running = false;
      _changeBus.notify();
    }
  }

  /// Returns true if at least one queue item was processed this pass.
  Future<bool> _drainPendingQueue() async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var afterId = 0;
    var processedAny = false;
    var skippedBlocked = 0;

    while (_connectivity.isOnline) {
      final item = await _local.getNextPendingQueueItem(nowMs, afterId: afterId);
      if (item == null || item.id == null) {
        break;
      }

      if (await _isBlocked(item)) {
        afterId = item.id!;
        skippedBlocked++;
        // Avoid infinite loop when every remaining item is blocked.
        if (skippedBlocked > 100) break;
        continue;
      }

      skippedBlocked = 0;
      await _processItem(item);
      processedAny = true;
      afterId = 0;
    }

    return processedAny;
  }

  Future<bool> _isBlocked(SyncQueueItem item) async {
    if (item.operation != QueueOperation.update) {
      return false;
    }
    if (item.serverId != null && item.serverId!.isNotEmpty) {
      return false;
    }
    return _local.hasPendingCreateForLocalId(item.localId);
  }

  Future<void> _processItem(SyncQueueItem item) async {
    final queueId = item.id!;
    developer.log(
      'sync_item operation=${item.operation.value} local_id=${item.localId}',
      name: 'SyncEngine',
    );

    await _local.markQueueInProgress(queueId);

    try {
      final payload = UserDto.parsePayload(item.payloadJson);

      if (item.operation == QueueOperation.create) {
        final response = await _remote.createUser(
          payload: payload,
          localId: item.localId,
        );
        final serverId = UserDto.parseServerId(response)!;

        await _local.markUserSyncedAfterCreate(
          localId: item.localId,
          serverId: serverId,
          name: payload['name']?.toString() ?? '',
          email: payload['email']?.toString() ?? '',
          job: payload['job']?.toString(),
        );
      } else {
        final serverId = item.serverId;
        if (serverId == null || serverId.isEmpty) {
          throw StateError('UPDATE queue item missing server_id');
        }

        await _remote.updateUser(
          serverId: serverId,
          payload: payload,
          localId: item.localId,
        );

        await _local.markUserSyncedAfterUpdate(
          localId: item.localId,
          name: payload['name']?.toString() ?? '',
          email: payload['email']?.toString() ?? '',
          job: payload['job']?.toString(),
        );
      }

      await _local.deleteQueueItem(queueId);
      developer.log(
        'sync_success local_id=${item.localId}',
        name: 'SyncEngine',
      );
    } catch (error, stackTrace) {
      final errorClass = SyncPolicy.classify(error);
      final message = error.toString();
      final nextAttempt = item.attemptCount + 1;

      developer.log(
        'sync_failed local_id=${item.localId} attempt=$nextAttempt error=$message',
        name: 'SyncEngine',
        error: error,
        stackTrace: stackTrace,
      );

      if (errorClass == SyncErrorClass.nonRetryable ||
          nextAttempt >= SyncPolicy.maxAttempts) {
        await _local.markQueueAndUserFailed(
          queueId: queueId,
          localId: item.localId,
          error: message,
        );
      } else {
        final delay = SyncPolicy.backoffForAttempt(nextAttempt);
        developer.log(
          'sync_retry local_id=${item.localId} in=${delay.inSeconds}s',
          name: 'SyncEngine',
        );
        await _local.markQueueRetry(
          queueId: queueId,
          attemptCount: nextAttempt,
          nextAttemptAt: DateTime.now().add(delay),
          error: message,
        );
      }
    }
  }
}
