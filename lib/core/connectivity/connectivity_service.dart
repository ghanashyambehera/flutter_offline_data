import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final _onlineController = StreamController<bool>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _debounceTimer;
  bool _isOnline = false;
  bool _initialized = false;

  Stream<bool> get isOnlineStream => _onlineController.stream;

  bool get isOnline => _isOnline;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final initial = await _connectivity.checkConnectivity();
    _emitOnline(_mapConnectivity(initial));

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 400), () {
        _emitOnline(_mapConnectivity(results));
      });
    });
  }

  bool _mapConnectivity(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any(
      (result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet,
    );
  }

  void _emitOnline(bool online) {
    if (_isOnline == online && _onlineController.hasListener) {
      return;
    }
    _isOnline = online;
    if (!_onlineController.isClosed) {
      _onlineController.add(online);
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
    _subscription?.cancel();
    _onlineController.close();
  }
}
