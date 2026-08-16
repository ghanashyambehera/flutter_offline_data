import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/connectivity/connectivity_service.dart';
import 'core/database/database_change_bus.dart';
import 'core/network/dio_client.dart';
import 'features/users/data/datasources/user_local_datasource.dart';
import 'features/users/data/datasources/user_remote_datasource.dart';
import 'features/users/data/repositories/user_repository_impl.dart';
import 'features/users/domain/repositories/user_repository.dart';
import 'features/users/presentation/user_list_page.dart';
import 'features/users/sync/sync_coordinator.dart';
import 'features/users/sync/sync_engine.dart';

class OfflineSyncApp extends StatefulWidget {
  const OfflineSyncApp({super.key});

  @override
  State<OfflineSyncApp> createState() => _OfflineSyncAppState();
}

class _OfflineSyncAppState extends State<OfflineSyncApp> {
  late final DatabaseChangeBus _changeBus;
  late final ConnectivityService _connectivityService;
  late final DioClient _dioClient;
  late final UserLocalDataSource _localDataSource;
  late final UserRemoteDataSource _remoteDataSource;
  late final SyncEngine _syncEngine;
  late final UserRepositoryImpl _userRepository;
  late final SyncCoordinator _syncCoordinator;

  @override
  void initState() {
    super.initState();
    _changeBus = DatabaseChangeBus();
    _connectivityService = ConnectivityService();
    _dioClient = DioClient();
    _localDataSource = UserLocalDataSource(_changeBus);
    _remoteDataSource = UserRemoteDataSource(_dioClient);
    _syncEngine = SyncEngine(
      localDataSource: _localDataSource,
      remoteDataSource: _remoteDataSource,
      connectivityService: _connectivityService,
      changeBus: _changeBus,
    );
    _userRepository = UserRepositoryImpl(
      localDataSource: _localDataSource,
      syncEngine: _syncEngine,
      connectivityService: _connectivityService,
      changeBus: _changeBus,
    );
    _syncCoordinator = SyncCoordinator(
      syncEngine: _syncEngine,
      connectivityService: _connectivityService,
      localDataSource: _localDataSource,
    );
    _syncCoordinator.start();
  }

  @override
  void dispose() {
    _syncCoordinator.dispose();
    _connectivityService.dispose();
    _changeBus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<UserRepository>.value(value: _userRepository),
        Provider<ConnectivityService>.value(value: _connectivityService),
      ],
      child: MaterialApp(
        title: 'Offline Data Sync',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
        ),
        home: const UserListPage(),
      ),
    );
  }
}
