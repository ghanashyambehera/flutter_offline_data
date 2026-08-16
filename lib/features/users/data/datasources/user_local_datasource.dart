import 'package:sqflite/sqflite.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_change_bus.dart';
import '../../domain/entities/user.dart';
import '../models/sync_queue_item.dart';
import '../models/user_dto.dart';
import '../models/user_local.dart';

class UserLocalDataSource {
  UserLocalDataSource(this._changeBus);

  final DatabaseChangeBus _changeBus;
  Database? _db;
  static const String _usersTable = 'users';
  //sync_queue
  static const String _syncQueueTable = 'sync_queue';

  Future<Database> get db async {
    _db ??= await AppDatabase.instance;
    return _db!;
  }

  Future<List<UserLocal>> getAllUsers() async {
    final database = await db;
    final rows = await database.query(
      _usersTable,
      orderBy: 'updated_at DESC',
    );
    return rows.map(UserLocal.fromMap).toList();
  }

  Future<UserLocal?> getUserByLocalId(String localId) async {
    final database = await db;
    final rows = await database.query(
      _usersTable,
      where: 'local_id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return UserLocal.fromMap(rows.first);
  }

  Future<SyncQueueItem?> findPendingCreateQueueItem(String localId) async {
    final database = await db;
    final rows = await database.query(
      _syncQueueTable,
      where:
          'local_id = ? AND operation = ? AND status IN (?, ?)',
      whereArgs: [
        localId,
        QueueOperation.create.value,
        QueueStatus.pending.value,
        QueueStatus.inProgress.value,
      ],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SyncQueueItem.fromMap(rows.first);
  }

  Future<SyncQueueItem?> findPendingUpdateQueueItem(String localId) async {
    final database = await db;
    final rows = await database.query(
      _syncQueueTable,
      where:
          'local_id = ? AND operation = ? AND status = ?',
      whereArgs: [
        localId,
        QueueOperation.update.value,
        QueueStatus.pending.value,
      ],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SyncQueueItem.fromMap(rows.first);
  }

  Future<bool> hasPendingCreateForLocalId(String localId) async {
    final database = await db;
    final rows = await database.query(
      _syncQueueTable,
      columns: ['id'],
      where:
          'local_id = ? AND operation = ? AND status IN (?, ?, ?)',
      whereArgs: [
        localId,
        QueueOperation.create.value,
        QueueStatus.pending.value,
        QueueStatus.inProgress.value,
        QueueStatus.failed.value,
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<SyncQueueItem?> getNextPendingQueueItem(
    int nowMs, {
    int afterId = 0,
  }) async {
    final database = await db;
    final rows = await database.query(
      _syncQueueTable,
      where:
          'status = ? AND (next_attempt_at IS NULL OR next_attempt_at <= ?) AND id > ?',
      whereArgs: [QueueStatus.pending.value, nowMs, afterId],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SyncQueueItem.fromMap(rows.first);
  }

  Future<int> countReadyPendingQueueItems() async {
    final database = await db;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final result = await database.rawQuery(
      '''
      SELECT COUNT(*) AS count FROM $_syncQueueTable
      WHERE status = ?
        AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
      ''',
      [QueueStatus.pending.value, nowMs],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<UserLocal> insertUserWithCreateQueue({
    required String localId,
    required String name,
    required String email,
    String? job,
    required String payloadJson,
  }) async {
    final database = await db;
    final now = DateTime.now();

    await database.transaction((txn) async {
      final nowMs = now.millisecondsSinceEpoch;
      await txn.insert('users', {
        'local_id': localId,
        'server_id': null,
        'name': name,
        'email': email,
        'job': job,
        'sync_status': SyncStatus.pendingCreate.value,
        'created_at': nowMs,
        'updated_at': nowMs,
        'last_error': null,
      });

      await txn.insert('sync_queue', {
        'entity_type': 'user',
        'operation': QueueOperation.create.value,
        'local_id': localId,
        'server_id': null,
        'payload_json': payloadJson,
        'status': QueueStatus.pending.value,
        'attempt_count': 0,
        'next_attempt_at': null,
        'last_error': null,
        'created_at': nowMs,
        'updated_at': nowMs,
      });
    });

    _changeBus.notify();
    return (await getUserByLocalId(localId))!;
  }

  Future<UserLocal> updateUserWithQueueCoalesce({
    required String localId,
    required String name,
    required String email,
    String? job,
    required String payloadJson,
  }) async {
    final database = await db;
    final existing = await getUserByLocalId(localId);
    if (existing == null) {
      throw StateError('User not found: $localId');
    }

    final now = DateTime.now();

    await database.transaction((txn) async {
      final nowMs = now.millisecondsSinceEpoch;

      if (existing.serverId == null) {
        await txn.update(
          'users',
          {
            'name': name,
            'email': email,
            'job': job,
            'sync_status': SyncStatus.pendingCreate.value,
            'updated_at': nowMs,
          },
          where: 'local_id = ?',
          whereArgs: [localId],
        );

        final updated = await txn.update(
          'sync_queue',
          {
            'payload_json': payloadJson,
            'updated_at': nowMs,
          },
          where:
              'local_id = ? AND operation = ? AND status IN (?, ?)',
          whereArgs: [
            localId,
            QueueOperation.create.value,
            QueueStatus.pending.value,
            QueueStatus.inProgress.value,
          ],
        );

        if (updated == 0) {
          await txn.insert('sync_queue', {
            'entity_type': 'user',
            'operation': QueueOperation.create.value,
            'local_id': localId,
            'server_id': null,
            'payload_json': payloadJson,
            'status': QueueStatus.pending.value,
            'attempt_count': 0,
            'next_attempt_at': null,
            'last_error': null,
            'created_at': nowMs,
            'updated_at': nowMs,
          });
        }
      } else {
        await txn.update(
          'users',
          {
            'name': name,
            'email': email,
            'job': job,
            'sync_status': SyncStatus.pendingUpdate.value,
            'updated_at': nowMs,
          },
          where: 'local_id = ?',
          whereArgs: [localId],
        );

        final updated = await txn.update(
          'sync_queue',
          {
            'payload_json': payloadJson,
            'server_id': existing.serverId,
            'updated_at': nowMs,
          },
          where:
              'local_id = ? AND operation = ? AND status = ?',
          whereArgs: [
            localId,
            QueueOperation.update.value,
            QueueStatus.pending.value,
          ],
        );

        if (updated == 0) {
          await txn.insert('sync_queue', {
            'entity_type': 'user',
            'operation': QueueOperation.update.value,
            'local_id': localId,
            'server_id': existing.serverId,
            'payload_json': payloadJson,
            'status': QueueStatus.pending.value,
            'attempt_count': 0,
            'next_attempt_at': null,
            'last_error': null,
            'created_at': nowMs,
            'updated_at': nowMs,
          });
        }
      }
    });

    _changeBus.notify();
    return (await getUserByLocalId(localId))!;
  }

  Future<void> markQueueInProgress(int queueId) async {
    final database = await db;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await database.update(
      'sync_queue',
      {'status': QueueStatus.inProgress.value, 'updated_at': nowMs},
      where: 'id = ?',
      whereArgs: [queueId],
    );
  }

  Future<void> deleteQueueItem(int queueId) async {
    final database = await db;
    await database.delete(
      'sync_queue',
      where: 'id = ?',
      whereArgs: [queueId],
    );
  }

  Future<void> markQueueRetry({
    required int queueId,
    required int attemptCount,
    required DateTime nextAttemptAt,
    required String error,
  }) async {
    final database = await db;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await database.update(
      'sync_queue',
      {
        'status': QueueStatus.pending.value,
        'attempt_count': attemptCount,
        'next_attempt_at': nextAttemptAt.millisecondsSinceEpoch,
        'last_error': error,
        'updated_at': nowMs,
      },
      where: 'id = ?',
      whereArgs: [queueId],
    );
  }

  Future<void> markQueueAndUserFailed({
    required int queueId,
    required String localId,
    required String error,
  }) async {
    final database = await db;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await database.transaction((txn) async {
      await txn.update(
        'sync_queue',
        {
          'status': QueueStatus.failed.value,
          'last_error': error,
          'updated_at': nowMs,
        },
        where: 'id = ?',
        whereArgs: [queueId],
      );
      await txn.update(
        'users',
        {
          'sync_status': SyncStatus.failed.value,
          'last_error': error,
          'updated_at': nowMs,
        },
        where: 'local_id = ?',
        whereArgs: [localId],
      );
    });
    _changeBus.notify();
  }

  Future<void> markUserSyncedAfterCreate({
    required String localId,
    required String serverId,
    required String name,
    required String email,
    String? job,
  }) async {
    final database = await db;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await database.transaction((txn) async {
      await txn.update(
        'users',
        {
          'server_id': serverId,
          'name': name,
          'email': email,
          'job': job,
          'sync_status': SyncStatus.synced.value,
          'last_error': null,
          'updated_at': nowMs,
        },
        where: 'local_id = ?',
        whereArgs: [localId],
      );
      await txn.update(
        'sync_queue',
        {'server_id': serverId},
        where: 'local_id = ?',
        whereArgs: [localId],
      );
    });
    _changeBus.notify();
  }

  Future<void> markUserSyncedAfterUpdate({
    required String localId,
    required String name,
    required String email,
    String? job,
  }) async {
    final database = await db;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await database.update(
      'users',
      {
        'name': name,
        'email': email,
        'job': job,
        'sync_status': SyncStatus.synced.value,
        'last_error': null,
        'updated_at': nowMs,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
    _changeBus.notify();
  }

  static String buildPayload({
    required String name,
    required String email,
    String? job,
    required String localId,
  }) {
    return UserDto.fromUserFields(
      name: name,
      email: email,
      job: job,
      localId: localId,
    ).toPayloadJson();
  }
}
