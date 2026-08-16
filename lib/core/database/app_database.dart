import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'tables.dart';

class AppDatabase {
  AppDatabase._();

  static const String dbName = 'offline_sync.db';
  static const int dbVersion = 2;

  static Database? _database;

  static Future<Database> get instance async {
    _database ??= await _open();
    return _database!;
  }

  static Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, dbName);

    return openDatabase(
      path,
      version: dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute(Tables.createUsersTable);
    await db.execute(Tables.createUsersSyncStatusIndex);
    await db.execute(Tables.createUsersServerIdIndex);
    await db.execute(Tables.createSyncQueueTable);
    await db.execute(Tables.createQueueStatusIndex);
    await db.execute(Tables.createQueueLocalIdIndex);
  }

  static Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _migrateV2RemoveServerIdUnique(db);
    }
  }

  /// v2: Drop UNIQUE on server_id — JSONPlaceholder returns duplicate ids.
  static Future<void> _migrateV2RemoveServerIdUnique(Database db) async {
    await db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE users_new (
          local_id TEXT PRIMARY KEY,
          server_id TEXT,
          name TEXT NOT NULL,
          email TEXT NOT NULL,
          job TEXT,
          sync_status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          last_error TEXT
        )
      ''');
      await txn.execute('''
        INSERT INTO users_new
        SELECT local_id, server_id, name, email, job, sync_status,
               created_at, updated_at, last_error
        FROM users
      ''');
      await txn.execute('DROP TABLE users');
      await txn.execute('ALTER TABLE users_new RENAME TO users');
      await txn.execute(Tables.createUsersSyncStatusIndex);
      await txn.execute(Tables.createUsersServerIdIndex);

      // Recover rows stuck failed due to duplicate server_id constraint.
      await txn.rawUpdate('''
        UPDATE sync_queue
        SET status = 'pending',
            attempt_count = 0,
            next_attempt_at = NULL,
            last_error = NULL,
            updated_at = ?
        WHERE status = 'failed'
          AND last_error LIKE '%UNIQUE constraint failed: users.server_id%'
      ''', [DateTime.now().millisecondsSinceEpoch]);

      await txn.rawUpdate('''
        UPDATE users
        SET sync_status = CASE
              WHEN sync_status = 'failed' THEN 'pending_create'
              ELSE sync_status
            END,
            last_error = NULL,
            updated_at = ?
        WHERE sync_status = 'failed'
          AND last_error LIKE '%UNIQUE constraint failed: users.server_id%'
      ''', [DateTime.now().millisecondsSinceEpoch]);
    });
  }

  static Future<void> resetInProgressQueue(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'sync_queue',
      {'status': 'pending', 'updated_at': now},
      where: 'status = ?',
      whereArgs: ['in_progress'],
    );
  }

  static Future<int> countPendingQueueItems(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = await db.rawQuery('''
      SELECT COUNT(*) AS count FROM sync_queue
      WHERE status = 'pending'
        AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
    ''', [now]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  /// Clears the on-disk database. Use in unit tests only.
  static Future<void> resetForTests() async {
    await close();
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, dbName);
    if (await databaseExists(path)) {
      await deleteDatabase(path);
    }
  }
}
