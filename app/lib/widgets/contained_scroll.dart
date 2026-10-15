import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Claim wheel events even at the list boundary, preventing nested scroll chaining.
class ContainedScroll extends StatelessWidget {
  const ContainedScroll({
    super.key,
    required this.controller,
    required this.child,
  });
  final ScrollController controller;
  final Widget child;
  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerSignal: (event) {
      if (event is! PointerScrollEvent) return;
      GestureBinding.instance.pointerSignalResolver.register(event, (signal) {
        if (!controller.hasClients) return;
        final position = controller.position;
        if (!position.hasContentDimensions) return;
        final next =
            (position.pixels + (signal as PointerScrollEvent).scrollDelta.dy)
                .clamp(position.minScrollExtent, position.maxScrollExtent);
        if (next != position.pixels) controller.jumpTo(next);
      });
    },
    child: child,
  );
}
