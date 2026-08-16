class Tables {
  /// server_id is NOT unique: JSONPlaceholder returns the same id (e.g. 11)
  /// for every POST. local_id remains the primary identity.
  static const String createUsersTable = '''
    CREATE TABLE users (
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
  ''';

  static const String createUsersSyncStatusIndex =
      'CREATE INDEX idx_users_sync_status ON users(sync_status)';

  static const String createUsersServerIdIndex =
      'CREATE INDEX idx_users_server_id ON users(server_id)';

  static const String createSyncQueueTable = '''
    CREATE TABLE sync_queue (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL,
      operation TEXT NOT NULL,
      local_id TEXT NOT NULL,
      server_id TEXT,
      payload_json TEXT NOT NULL,
      status TEXT NOT NULL,
      attempt_count INTEGER NOT NULL DEFAULT 0,
      next_attempt_at INTEGER,
      last_error TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (local_id) REFERENCES users(local_id) ON DELETE CASCADE
    )
  ''';

  static const String createQueueStatusIndex =
      'CREATE INDEX idx_queue_status ON sync_queue(status)';

  static const String createQueueLocalIdIndex =
      'CREATE INDEX idx_queue_local_id ON sync_queue(local_id)';
}
