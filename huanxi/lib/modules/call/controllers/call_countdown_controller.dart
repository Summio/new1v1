import 'dart:async';

class CallCountdownController {
  Timer? _timer;
  int _leftSeconds = 0;

  int get leftSeconds => _leftSeconds;

  void start({
    required int initialSeconds,
    required void Function(int leftSeconds) onTick,
    required void Function() onTimeout,
  }) {
    stop();
    _leftSeconds = initialSeconds > 0 ? initialSeconds : 0;
    if (_leftSeconds <= 0) {
      onTimeout();
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_leftSeconds <= 0) {
        timer.cancel();
        onTimeout();
        return;
      }
      _leftSeconds -= 1;
      onTick(_leftSeconds);
      if (_leftSeconds <= 0) {
        timer.cancel();
        onTimeout();
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
  }
}
