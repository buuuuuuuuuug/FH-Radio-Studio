import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

const playlistDragDistance = 10.0;

/// Waits for movement even when no other gesture competes for the pointer.
class PlaylistDraggable<T extends Object> extends Draggable<T> {
  const PlaylistDraggable({
    super.key,
    required super.data,
    required super.feedback,
    required super.child,
    super.childWhenDragging,
    super.maxSimultaneousDrags,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) =>
      _MovementDragRecognizer(allowedButtonsFilter: allowedButtonsFilter)
        ..onStart = onStart;
}

class _MovementDragRecognizer extends ImmediateMultiDragGestureRecognizer {
  _MovementDragRecognizer({super.allowedButtonsFilter});

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _MovementPointerState(event.position, event.kind, gestureSettings);
}

class _MovementPointerState extends MultiDragPointerState {
  _MovementPointerState(
    super.initialPosition,
    super.kind,
    super.gestureSettings,
  );
  GestureMultiDragStartCallback? _starter;

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    if (pendingDelta!.distance >= playlistDragDistance) {
      starter(initialPosition);
    } else {
      // The gesture arena can accept the sole recognizer on pointer down.
      _starter = starter;
    }
  }

  @override
  void checkForResolutionAfterMove() {
    if (pendingDelta!.distance < playlistDragDistance) return;
    final starter = _starter;
    if (starter == null) {
      resolve(GestureDisposition.accepted);
    } else {
      _starter = null;
      starter(initialPosition);
    }
  }

  @override
  void dispose() {
    _starter = null;
    super.dispose();
  }
}
