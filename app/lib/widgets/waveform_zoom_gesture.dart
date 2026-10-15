import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Claims Ctrl+wheel only inside the waveform; normal wheel still scrolls pages.
class WaveformZoomGesture extends StatelessWidget {
  const WaveformZoomGesture({
    super.key,
    required this.onZoom,
    required this.child,
  });
  final ValueChanged<double>? onZoom;
  final Widget child;
  @override
  Widget build(BuildContext context) => onZoom == null
      ? child
      : Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (event) {
            if (event is! PointerScrollEvent ||
                !HardwareKeyboard.instance.isControlPressed ||
                event.scrollDelta.dy == 0) {
              return;
            }
            GestureBinding.instance.pointerSignalResolver.register(event, (
              signal,
            ) {
              final delta = (signal as PointerScrollEvent).scrollDelta.dy.clamp(
                -240,
                240,
              );
              onZoom!(math.pow(1.5, delta / 240).toDouble());
            });
          },
          child: child,
        );
}
