import 'editor_timecode.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../../domain/replacement_models.dart';
import '../../theme/app_theme.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/rm_icon.dart';
import 'replace_state.dart';

/// 4 宫格 progress strip（TD/PD/TL/PL，按这个顺序显示）。
class ProgressStrip extends StatefulWidget {
  const ProgressStrip({
    super.key,
    required this.state,
    this.onSelect,
    this.onManualRefine,
    this.onQuickConfirm,
  });

  final ReplaceEditorState state;
  final ValueChanged<GroupKind>? onSelect, onManualRefine, onQuickConfirm;

  @override
  State<ProgressStrip> createState() => _ProgressStripState();
}

class _ProgressStripState extends State<ProgressStrip> {
  GroupKind? selectedGroup;
  ReplaceEditorState get state => widget.state;
  @override
  void didUpdateWidget(covariant ProgressStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.trackId != state.trackId) selectedGroup = null;
  }

  @override
  Widget build(BuildContext context) {
    final rm = context.rm;
    final cells = <_Cell>[
      _Cell(
        kind: GroupKind.td,
        label: 'TrackDrop · 比赛开始',
        confirmed: state.tdConfirmed,
        value: formatEditorTimecode(state.td.t),
      ),
      _Cell(
        kind: GroupKind.pd,
        label: 'PostDrop · 冲线后',
        confirmed: state.pdConfirmed,
        value: formatEditorTimecode(state.pd.t),
      ),
      _Cell(
        kind: GroupKind.tl,
        label: 'TrackLoop · 比赛循环',
        confirmed: state.tlConfirmed,
        value:
            '${formatEditorTimecode(state.tl.start)} → ${formatEditorTimecode(state.tl.end)}',
      ),
      _Cell(
        kind: GroupKind.pl,
        label: 'PostLoop · 冲线循环',
        confirmed: state.plConfirmed,
        value:
            '${formatEditorTimecode(state.pl.start)} → ${formatEditorTimecode(state.pl.end)}',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: rm.panel,
        border: Border.all(color: rm.border),
        borderRadius: BorderRadius.circular(RmTokens.rLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('双击人工精修 · Ctrl+右键快速确认', style: RmText.sans(10.5, color: rm.fg3)),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, c) {
              const minCellW = 180.0;
              final cols = (c.maxWidth / (minCellW + 8)).floor().clamp(1, 4);
              final cellW = (c.maxWidth - 8 * (cols - 1)) / cols;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final cell in cells)
                    SizedBox(
                      width: cellW,
                      child: _ProgressCell(
                        cell: cell,
                        selected: selectedGroup == cell.kind,
                        onSelect: () {
                          setState(() => selectedGroup = cell.kind);
                          widget.onSelect?.call(cell.kind);
                        },
                        onManualRefine: () {
                          setState(() => selectedGroup = cell.kind);
                          widget.onManualRefine?.call(cell.kind);
                        },
                        onQuickConfirm: () =>
                            widget.onQuickConfirm?.call(cell.kind),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Cell {
  const _Cell({
    required this.kind,
    required this.label,
    required this.confirmed,
    required this.value,
  });
  final GroupKind kind;
  final String label;
  final bool confirmed;
  final String value;
}

class _ProgressCell extends StatefulWidget {
  const _ProgressCell({
    required this.cell,
    required this.selected,
    required this.onSelect,
    required this.onManualRefine,
    required this.onQuickConfirm,
  });
  final _Cell cell;
  final bool selected;
  final VoidCallback onSelect, onManualRefine, onQuickConfirm;
  @override
  State<_ProgressCell> createState() => _ProgressCellState();
}

class _ProgressCellState extends State<_ProgressCell> {
  bool hovered = false;
  _Cell get cell => widget.cell;

  @override
  Widget build(BuildContext context) {
    final rm = context.rm;
    final confirmed = cell.confirmed;
    final active = widget.selected || hovered;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: '${cell.kind.code}，双击人工选点；Ctrl+鼠标右键快速确认',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: GestureDetector(
          key: ValueKey('editor-progress-${cell.kind.code}'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSelect,
          onDoubleTap: widget.onManualRefine,
          onSecondaryTap: () {
            if (!cell.confirmed && HardwareKeyboard.instance.isControlPressed) {
              widget.onQuickConfirm();
            }
          },
          child: Container(
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(RmTokens.rSm),
              gradient: active
                  ? const SweepGradient(
                      colors: [
                        Color(0xFFFF3CAC),
                        Color(0xFFFFA928),
                        Color(0xFF00F5A0),
                        Color(0xFF00D9FF),
                        Color(0xFF6C63FF),
                        Color(0xFFFF3CAC),
                      ],
                    )
                  : null,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: confirmed
                    ? Color.alphaBlend(rm.accent.bg, rm.panel)
                    : rm.raised,
                border: Border.all(
                  color: active
                      ? Colors.transparent
                      : confirmed
                      ? rm.accent.ring
                      : rm.borderStrong,
                ),
                borderRadius: BorderRadius.circular(RmTokens.rSm),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cell.kind.code,
                          style: RmText.mono(
                            11,
                            weight: FontWeight.w600,
                            letterSpacing: 0.05 * 11,
                            color: confirmed ? rm.accent.base : rm.fg2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cell.label,
                          style: RmText.sans(11.5, color: rm.fg3),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cell.value,
                          style: RmText.mono(10.5, color: rm.fg3),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: confirmed ? rm.accent.base : Colors.transparent,
                      border: Border.all(
                        color: confirmed ? rm.accent.base : rm.borderStrong,
                      ),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: confirmed
                        ? RmIcon('check', size: 10, color: rm.accent.onAccent)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
