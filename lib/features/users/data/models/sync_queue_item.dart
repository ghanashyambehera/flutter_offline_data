enum QueueOperation {
  create('CREATE'),
  update('UPDATE');

  const QueueOperation(this.value);

  final String value;

  static QueueOperation fromValue(String value) {
    return QueueOperation.values.firstWhere(
      (operation) => operation.value == value,
    );
  }
}

enum QueueStatus {
  pending('pending'),
  inProgress('in_progress'),
  done('done'),
  failed('failed');

  const QueueStatus(this.value);

  final String value;

  static QueueStatus fromValue(String value) {
    return QueueStatus.values.firstWhere(
      (status) => status.value == value,
    );
  }
}

class SyncQueueItem {
  SyncQueueItem({
    this.id,
    required this.entityType,
    required this.operation,
    required this.localId,
    this.serverId,
    required this.payloadJson,
    required this.status,
    required this.attemptCount,
    this.nextAttemptAt,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String entityType;
  final QueueOperation operation;
  final String localId;
  final String? serverId;
  final String payloadJson;
  final QueueStatus status;
  final int attemptCount;
  final DateTime? nextAttemptAt;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory SyncQueueItem.fromMap(Map<String, Object?> map) {
    return SyncQueueItem(
      id: map['id'] as int?,
      entityType: map['entity_type']! as String,
      operation: QueueOperation.fromValue(map['operation']! as String),
      localId: map['local_id']! as String,
      serverId: map['server_id'] as String?,
      payloadJson: map['payload_json']! as String,
      status: QueueStatus.fromValue(map['status']! as String),
      attemptCount: map['attempt_count']! as int,
      nextAttemptAt: map['next_attempt_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              map['next_attempt_at']! as int,
            ),
      lastError: map['last_error'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at']! as int),
    );
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    final map = <String, Object?>{
      'entity_type': entityType,
      'operation': operation.value,
      'local_id': localId,
      'server_id': serverId,
      'payload_json': payloadJson,
      'status': status.value,
      'attempt_count': attemptCount,
      'next_attempt_at': nextAttemptAt?.millisecondsSinceEpoch,
      'last_error': lastError,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
    if (includeId && id != null) {
      map['id'] = id;
    }
    return map;
  }
}
