import 'dart:async';

class DatabaseChangeBus {
  final _controller = StreamController<void>.broadcast();

  Stream<void> get changes => _controller.stream;

  void notify() {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }

  void dispose() {
    _controller.close();
  }
}
