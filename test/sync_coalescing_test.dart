import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_offline_data/core/database/app_database.dart';
import 'package:flutter_offline_data/core/database/database_change_bus.dart';
import 'package:flutter_offline_data/core/connectivity/connectivity_service.dart';
import 'package:flutter_offline_data/core/network/dio_client.dart';
import 'package:flutter_offline_data/features/users/data/datasources/user_local_datasource.dart';
import 'package:flutter_offline_data/features/users/data/datasources/user_remote_datasource.dart';
import 'package:flutter_offline_data/features/users/data/repositories/user_repository_impl.dart';
import 'package:flutter_offline_data/features/users/domain/validation/user_validator.dart';
import 'package:flutter_offline_data/features/users/sync/sync_engine.dart';

class FakeConnectivityService extends ConnectivityService {
  FakeConnectivityService({this.online = false});

  bool online;

  @override
  bool get isOnline => online;

  @override
  Future<void> initialize() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await AppDatabase.resetForTests();
  });

  tearDown(() async {
    await AppDatabase.resetForTests();
  });

  group('UserValidator', () {
    test('rejects empty name', () {
      expect(
        () => UserValidator.validate(name: '', email: 'a@b.com'),
        throwsA(isA<UserValidationException>()),
      );
    });

    test('accepts valid input', () {
      expect(
        () => UserValidator.validate(
          name: 'Jane',
          email: 'jane@example.com',
          job: 'Engineer',
        ),
        returnsNormally,
      );
    });
  });

  group('Sync coalescing', () {
    test('create then update before sync keeps one CREATE queue row', () async {
      final changeBus = DatabaseChangeBus();
      final local = UserLocalDataSource(changeBus);
      final connectivity = FakeConnectivityService();
      final syncEngine = SyncEngine(
        localDataSource: local,
        remoteDataSource: UserRemoteDataSource(DioClient()),
        connectivityService: connectivity,
        changeBus: changeBus,
      );
      final repository = UserRepositoryImpl(
        localDataSource: local,
        syncEngine: syncEngine,
        connectivityService: connectivity,
        changeBus: changeBus,
      );

      final created = await repository.createUser(
        name: 'Alice',
        email: 'alice@example.com',
      );

      await repository.updateUser(
        localId: created.localId,
        name: 'Alice Updated',
        email: 'alice.updated@example.com',
      );

      final db = await AppDatabase.instance;
      final queueRows = await db.query('sync_queue');
      expect(queueRows.length, 1);
      expect(queueRows.first['operation'], 'CREATE');
      expect(queueRows.first['payload_json'], contains('Alice Updated'));
    });
  });

  group('Duplicate JSONPlaceholder server_id', () {
    test('two users can store the same server_id locally', () async {
      final changeBus = DatabaseChangeBus();
      final local = UserLocalDataSource(changeBus);

      await local.insertUserWithCreateQueue(
        localId: 'local-a',
        name: 'User A',
        email: 'a@example.com',
        payloadJson: UserLocalDataSource.buildPayload(
          name: 'User A',
          email: 'a@example.com',
          localId: 'local-a',
        ),
      );

      await local.markUserSyncedAfterCreate(
        localId: 'local-a',
        serverId: '11',
        name: 'User A',
        email: 'a@example.com',
      );

      await local.insertUserWithCreateQueue(
        localId: 'local-b',
        name: 'User B',
        email: 'b@example.com',
        payloadJson: UserLocalDataSource.buildPayload(
          name: 'User B',
          email: 'b@example.com',
          localId: 'local-b',
        ),
      );

      await local.markUserSyncedAfterCreate(
        localId: 'local-b',
        serverId: '11',
        name: 'User B',
        email: 'b@example.com',
      );

      final db = await AppDatabase.instance;
      final rows = await db.query(
        'users',
        where: 'server_id = ?',
        whereArgs: ['11'],
      );
      expect(rows.length, 2);
    });
  });

  group('Crash recovery', () {
    test('resets in_progress queue items to pending', () async {
      final changeBus = DatabaseChangeBus();
      final local = UserLocalDataSource(changeBus);

      await local.insertUserWithCreateQueue(
        localId: 'local-1',
        name: 'Bob',
        email: 'bob@example.com',
        payloadJson: UserLocalDataSource.buildPayload(
          name: 'Bob',
          email: 'bob@example.com',
          localId: 'local-1',
        ),
      );

      final db = await AppDatabase.instance;
      await db.update(
        'sync_queue',
        {'status': 'in_progress'},
        where: 'local_id = ?',
        whereArgs: ['local-1'],
      );

      await AppDatabase.resetInProgressQueue(db);

      final rows = await db.query('sync_queue');
      expect(rows.first['status'], 'pending');
    });
  });
}
