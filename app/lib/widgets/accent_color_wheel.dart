import 'dart:math' as math;
import 'package:flutter/material.dart';

class AccentColorWheel extends StatelessWidget {
  const AccentColorWheel({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final HSVColor value;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '点击或拖动色盘选择色相与饱和度，使用明度滑块调整亮度',
    child: Semantics(
      label: '强调色色盘',
      child: SizedBox(
        width: 176,
        height: 176,
        child: LayoutBuilder(
          builder: (context, c) {
            void choose(Offset position) {
              final delta = position - Offset(c.maxWidth / 2, c.maxHeight / 2);
              final radius = math.min(c.maxWidth, c.maxHeight) / 2 - 7;
              final hue = delta.distance < 0.001
                  ? value.hue
                  : (math.atan2(delta.dy, delta.dx) * 180 / math.pi + 360) %
                        360;
              onChanged(
                value
                    .withHue(hue)
                    .withSaturation((delta.distance / radius).clamp(0.0, 1.0)),
              );
            }

            return MouseRegion(
              cursor: SystemMouseCursors.precise,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: (event) => choose(event.localPosition),
                onPanStart: (event) => choose(event.localPosition),
                onPanUpdate: (event) => choose(event.localPosition),
                child: CustomPaint(painter: _ColorWheelPainter(value)),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _ColorWheelPainter extends CustomPainter {
  _ColorWheelPainter(this.value);
  final HSVColor value;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 7;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = SweepGradient(
          colors: List.generate(
            7,
            (i) => HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
          ),
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Colors.white, Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = Colors.black.withValues(alpha: 1 - value.value),
    );
    final angle = value.hue * math.pi / 180;
    final selection =
        center +
        Offset(math.cos(angle), math.sin(angle)) * radius * value.saturation;
    canvas.drawCircle(selection, 6, Paint()..color = value.toColor());
    canvas.drawCircle(
      selection,
      6,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );
    canvas.drawCircle(
      selection,
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ColorWheelPainter oldDelegate) =>
      oldDelegate.value != value;
}
