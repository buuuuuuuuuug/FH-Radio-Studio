import 'package:flutter/material.dart';

/// A static outline keeps transient notifications visible without animation.
class RainbowBorder extends RoundedRectangleBorder {
  const RainbowBorder()
    : super(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        side: const BorderSide(width: 1.5),
      );

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    const colors = [
      Color(0xFFFF3CAC),
      Color(0xFFFFA928),
      Color(0xFF00C981),
      Color(0xFF00B9DB),
      Color(0xFF6C63FF),
      Color(0xFFFF3CAC),
    ];
    canvas.drawRRect(
      borderRadius.resolve(textDirection).toRRect(rect.deflate(.75)),
      Paint()
        ..shader = const SweepGradient(colors: colors).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
}
