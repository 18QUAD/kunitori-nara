import 'dart:async';
import 'map_view.dart';

/// Keep the latest camera position in memory while pan/zoom is producing frames.
/// Persist after a short pause, or once a second during a continuous gesture.
class MapViewSaveQueue {
  MapViewSaveQueue(this.save);
  final Future<void> Function(MapViewState) save;
  Timer? _idle, _deadline;
  MapViewState? _pending;
  bool _disposed = false;

  void schedule(MapViewState view) {
    if (_disposed) return;
    _pending = view;
    _idle?.cancel();
    _idle = Timer(const Duration(milliseconds: 250), () => unawaited(flush()));
    _deadline ??= Timer(const Duration(seconds: 1), () => unawaited(flush()));
  }

  Future<void> flush() {
    final view = _pending;
    cancel();
    return view == null ? Future<void>.value() : save(view);
  }

  void cancel() {
    _idle?.cancel();
    _deadline?.cancel();
    _idle = _deadline = null;
    _pending = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(flush());
  }
}
