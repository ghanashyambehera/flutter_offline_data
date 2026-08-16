import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/connectivity/connectivity_service.dart';
import '../domain/entities/user.dart';
import '../domain/repositories/user_repository.dart';
import 'user_form_page.dart';

class UserListPage extends StatelessWidget {
  const UserListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<UserRepository>();
    final connectivity = context.read<ConnectivityService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
      ),
      body: Column(
        children: [
          StreamBuilder<bool>(
            stream: connectivity.isOnlineStream,
            initialData: connectivity.isOnline,
            builder: (context, snapshot) {
              final isOnline = snapshot.data ?? true;
              if (isOnline) {
                return const SizedBox.shrink();
              }
              return MaterialBanner(
                content: const Text(
                  'Offline — changes will sync automatically',
                ),
                leading: const Icon(Icons.cloud_off),
                actions: const [SizedBox(width: 8)],
                backgroundColor: Colors.orange.shade100,
              );
            },
          ),
          Expanded(
            child: StreamBuilder<List<User>>(
              stream: repository.watchUsers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final users = snapshot.data ?? [];
                if (users.isEmpty) {
                  return const Center(
                    child: Text('No users yet. Tap + to create one.'),
                  );
                }

                return ListView.separated(
                  itemCount: users.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return ListTile(
                      title: Text(user.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.email),
                          if (user.lastError != null &&
                              user.syncStatus == SyncStatus.failed)
                            Text(
                              user.lastError!,
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                      trailing: _SyncStatusChip(status: user.syncStatus),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => UserFormPage(user: user),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const UserFormPage(),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _SyncStatusChip extends StatelessWidget {
  const _SyncStatusChip({required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final String label;

    switch (status) {
      case SyncStatus.synced:
        color = Colors.green;
        label = 'Synced';
      case SyncStatus.pendingCreate:
      case SyncStatus.pendingUpdate:
        color = Colors.orange;
        label = 'Pending';
      case SyncStatus.failed:
        color = Colors.red;
        label = 'Failed';
    }

    return Chip(
      label: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}
