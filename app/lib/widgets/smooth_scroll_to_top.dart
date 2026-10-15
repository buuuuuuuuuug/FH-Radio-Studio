import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import 'contained_scroll.dart';

/// Distant returns crossfade at the destination instead of building every row
/// along a several-thousand-pixel scroll animation.
class SmoothScrollToTop extends StatefulWidget {
  const SmoothScrollToTop({
    super.key,
    required this.controller,
    required this.child,
    this.bottom = 44,
    this.threshold = 500,
    this.compact = false,
    this.enabled = true,
  });
  final ScrollController controller;
  final Widget child;
  final double bottom, threshold;
  final bool compact;
  final bool enabled;
  @override
  State<SmoothScrollToTop> createState() => _SmoothScrollToTopState();
}

class _SmoothScrollToTopState extends State<SmoothScrollToTop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    value: 1,
  );
  bool _visible = false, _returning = false;
  @override
  void initState() {
    super.initState();
    _visible = widget.controller.initialScrollOffset > widget.threshold;
    widget.controller.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void didUpdateWidget(SmoothScrollToTop old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_update);
      widget.controller.addListener(_update);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  void _update() {
    if (!mounted) return;
    final visible =
        widget.enabled &&
        widget.controller.hasClients &&
        widget.controller.offset > widget.threshold;
    if (visible != _visible) setState(() => _visible = visible);
  }

  Future<void> _return() async {
    if (_returning || !widget.controller.hasClients) return;
    setState(() => _returning = true);
    final ctl = widget.controller;
    try {
      if (ctl.offset > ctl.position.viewportDimension * 2) {
        await _fade
            .animateTo(
              0,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            )
            .orCancel;
        if (!mounted || !ctl.hasClients) return;
        ctl.jumpTo(0);
        await _fade
            .animateTo(
              1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            )
            .orCancel;
      } else {
        await ctl.animateTo(
          0,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeInOutCubic,
        );
      }
    } on TickerCanceled {
      // The screen was closed during the return.
    } finally {
      if (mounted) {
        _fade.value = 1;
        setState(() => _returning = false);
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rm = context.rm;
    return ContainedScroll(
      controller: widget.controller,
      child: Stack(
        children: [
          FadeTransition(opacity: _fade, child: widget.child),
          if (_visible || _returning)
            Positioned(
              left: 0,
              right: 0,
              bottom: widget.bottom,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(RmTokens.rSm + 1.5),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF62DFC6),
                        Color(0xFF77C9FA),
                        Color(0xFFD693ED),
                        Color(0xFFF99EB3),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: rm.fg.withAlpha(28),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Material(
                    color: rm.panel,
                    borderRadius: BorderRadius.circular(RmTokens.rSm),
                    child: InkWell(
                      key: const ValueKey('scroll-to-top-button'),
                      borderRadius: BorderRadius.circular(RmTokens.rSm),
                      onTap: _returning ? null : () => unawaited(_return()),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: widget.compact ? 12 : 18,
                          vertical: widget.compact ? 8 : 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.vertical_align_top,
                              size: 15,
                              color: rm.fg2,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              '回到顶部',
                              style: RmText.sans(
                                12.5,
                                weight: FontWeight.w500,
                                color: rm.fg,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
