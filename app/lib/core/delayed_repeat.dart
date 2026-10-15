import 'dart:async';

/// A single press remains a single step. Holding starts repeating after 500 ms.
class DelayedRepeat {
  Timer? _delay, _interval;
  int _generation = 0;
  void start(void Function() action) {
    stop();
    final generation = _generation;
    _delay = Timer(const Duration(milliseconds: 500), () {
      action();
      if (generation != _generation) return;
      _interval = Timer.periodic(
        const Duration(milliseconds: 90),
        (_) => action(),
      );
    });
  }

  void stop() {
    _generation++;
    _delay?.cancel();
    _interval?.cancel();
    _delay = _interval = null;
  }
}
