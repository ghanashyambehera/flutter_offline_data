import '../../domain/entities/user.dart';

class UserLocal {
  UserLocal({
    required this.localId,
    this.serverId,
    required this.name,
    required this.email,
    this.job,
    required this.syncStatus,
    required this.createdAt,
    required this.updatedAt,
    this.lastError,
  });

  final String localId;
  final String? serverId;
  final String name;
  final String email;
  final String? job;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastError;

  factory UserLocal.fromMap(Map<String, Object?> map) {
    return UserLocal(
      localId: map['local_id']! as String,
      serverId: map['server_id'] as String?,
      name: map['name']! as String,
      email: map['email']! as String,
      job: map['job'] as String?,
      syncStatus: SyncStatus.fromValue(map['sync_status']! as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at']! as int),
      lastError: map['last_error'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'local_id': localId,
      'server_id': serverId,
      'name': name,
      'email': email,
      'job': job,
      'sync_status': syncStatus.value,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'last_error': lastError,
    };
  }

  User toEntity() {
    return User(
      localId: localId,
      serverId: serverId,
      name: name,
      email: email,
      job: job,
      syncStatus: syncStatus,
      updatedAt: updatedAt,
      lastError: lastError,
    );
  }
}
