import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/connectivity/connectivity_service.dart';
import '../data/datasources/user_local_datasource.dart';
import '../sync/sync_engine.dart';

class SyncCoordinator with WidgetsBindingObserver {
  SyncCoordinator({
    required SyncEngine syncEngine,
    required ConnectivityService connectivityService,
    required UserLocalDataSource localDataSource,
  })  : _syncEngine = syncEngine,
        _connectivity = connectivityService,
        _localDataSource = localDataSource;

  final SyncEngine _syncEngine;
  final ConnectivityService _connectivity;
  final UserLocalDataSource _localDataSource;

  StreamSubscription<bool>? _connectivitySubscription;
  bool _wasOnline = false;

  Future<void> start() async {
    await _connectivity.initialize();
    _wasOnline = _connectivity.isOnline;

    WidgetsBinding.instance.addObserver(this);

    _connectivitySubscription =
        _connectivity.isOnlineStream.listen((online) async {
      if (!_wasOnline && online) {
        await _runSyncUntilIdle();
      }
      _wasOnline = online;
    });

    if (_connectivity.isOnline) {
      await _runSyncUntilIdle();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _connectivity.isOnline) {
      unawaited(_runSyncUntilIdle());
    }
  }

  /// Keeps draining while pending queue items remain (multi-record sync).
  Future<void> _runSyncUntilIdle() async {
    var pending = await _localDataSource.countReadyPendingQueueItems();
    var attempts = 0;

    while (_connectivity.isOnline && pending > 0 && attempts < 20) {
      await _syncEngine.trySync();
      final remaining = await _localDataSource.countReadyPendingQueueItems();
      if (remaining >= pending) {
        // No progress — avoid tight loop (e.g. all items blocked or retry delayed).
        break;
      }
      pending = remaining;
      attempts++;
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
  }
}
