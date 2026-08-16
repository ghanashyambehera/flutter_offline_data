enum SyncStatus {
  pendingCreate('pending_create'),
  pendingUpdate('pending_update'),
  synced('synced'),
  failed('failed');

  const SyncStatus(this.value);

  final String value;

  static SyncStatus fromValue(String value) {
    return SyncStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => SyncStatus.pendingCreate,
    );
  }

  bool get isPending =>
      this == SyncStatus.pendingCreate || this == SyncStatus.pendingUpdate;
}

class User {
  const User({
    required this.localId,
    this.serverId,
    required this.name,
    required this.email,
    this.job,
    required this.syncStatus,
    required this.updatedAt,
    this.lastError,
  });

  final String localId;
  final String? serverId;
  final String name;
  final String email;
  final String? job;
  final SyncStatus syncStatus;
  final DateTime updatedAt;
  final String? lastError;
}
