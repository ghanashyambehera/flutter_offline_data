import 'dart:async';
import 'dart:developer' as developer;

import 'package:uuid/uuid.dart';

import '../../../../core/connectivity/connectivity_service.dart';
import '../../../../core/database/database_change_bus.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/user_repository.dart';
import '../../domain/validation/user_validator.dart';
import '../datasources/user_local_datasource.dart';
import '../../sync/sync_engine.dart';

class UserRepositoryImpl implements UserRepository {
  UserRepositoryImpl({
    required UserLocalDataSource localDataSource,
    required SyncEngine syncEngine,
    required ConnectivityService connectivityService,
    required DatabaseChangeBus changeBus,
    Uuid? uuid,
  })  : _local = localDataSource,
        _syncEngine = syncEngine,
        _connectivity = connectivityService,
        _changeBus = changeBus,
        _uuid = uuid ?? const Uuid();

  final UserLocalDataSource _local;
  final SyncEngine _syncEngine;
  final ConnectivityService _connectivity;
  final DatabaseChangeBus _changeBus;
  final Uuid _uuid;

  @override
  Stream<List<User>> watchUsers() async* {
    yield (await _local.getAllUsers()).map((user) => user.toEntity()).toList();

    await for (final _ in _changeBus.changes) {
      yield (await _local.getAllUsers()).map((user) => user.toEntity()).toList();
    }
  }

  @override
  Future<User> createUser({
    required String name,
    required String email,
    String? job,
  }) async {
    UserValidator.validate(name: name, email: email, job: job);

    final localId = _uuid.v4();
    final payload = UserLocalDataSource.buildPayload(
      name: name.trim(),
      email: email.trim(),
      job: job?.trim(),
      localId: localId,
    );

    final user = await _local.insertUserWithCreateQueue(
      localId: localId,
      name: name.trim(),
      email: email.trim(),
      job: job?.trim(),
      payloadJson: payload,
    );

    developer.log(
      'queue_enqueued operation=CREATE local_id=$localId',
      name: 'UserRepository',
    );

    unawaited(_triggerSyncIfOnline());
    return user.toEntity();
  }

  @override
  Future<User> updateUser({
    required String localId,
    required String name,
    required String email,
    String? job,
  }) async {
    UserValidator.validate(name: name, email: email, job: job);

    final payload = UserLocalDataSource.buildPayload(
      name: name.trim(),
      email: email.trim(),
      job: job?.trim(),
      localId: localId,
    );

    final user = await _local.updateUserWithQueueCoalesce(
      localId: localId,
      name: name.trim(),
      email: email.trim(),
      job: job?.trim(),
      payloadJson: payload,
    );

    developer.log(
      'queue_enqueued operation=UPDATE local_id=$localId',
      name: 'UserRepository',
    );

    unawaited(_triggerSyncIfOnline());
    return user.toEntity();
  }

  Future<void> _triggerSyncIfOnline() async {
    if (_connectivity.isOnline) {
      await _syncEngine.trySync();
    }
  }
}
