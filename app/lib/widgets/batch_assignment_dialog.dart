import '../theme/tokens.dart';
import 'package:flutter/material.dart';
import '../domain/radio_library.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import 'rm_button.dart';

class BatchAssignmentInfo {
  const BatchAssignmentInfo({
    required this.total,
    required this.added,
    required this.limit,
    required this.replacesBuiltin,
  });
  final int total;
  final int added;
  final int limit;
  final bool replacesBuiltin;
}

class BatchAssignmentDialog extends StatefulWidget {
  const BatchAssignmentDialog({
    super.key,
    required this.radios,
    required this.tracks,
    required this.splitTypes,
    required this.initialType,
    required this.info,
  });
  final List<RadioStation> radios;
  final List<PoolTrack> tracks;
  final bool splitTypes;
  final String initialType;
  final BatchAssignmentInfo Function(RadioStation, String) info;
  @override
  State<BatchAssignmentDialog> createState() => _BatchAssignmentDialogState();
}

class _BatchAssignmentDialogState extends State<BatchAssignmentDialog> {
  late String _radio = widget.radios.first.code;
  late String _type = widget.initialType;
  @override
  Widget build(BuildContext context) {
    final rm = context.rm;
    final radio = widget.radios.firstWhere((r) => r.code == _radio);
    final info = widget.info(radio, _type);
    final exceeds = info.total > info.limit;
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(
          primary: rm.accent.base,
          onPrimary: rm.accent.onAccent,
          surface: rm.panel,
        ),
      ),
      child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RmTokens.rLg),
          side: BorderSide(color: rm.border),
        ),
        backgroundColor: rm.panel,
        surfaceTintColor: Colors.transparent,
        title: Text(
          '分配 ${widget.tracks.length} 首歌曲',
          style: RmText.sans(15, weight: FontWeight.w600, color: rm.fg),
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _radio,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '目标电台'),
                  items: [
                    for (final r in widget.radios)
                      DropdownMenuItem(
                        value: r.code,
                        child: Text(
                          '${r.code} · ${r.name}',
                          overflow: TextOverflow.ellipsis,
                          style: RmText.sans(12.5, color: rm.fg),
                        ),
                      ),
                  ],
                  onChanged: (r) {
                    if (r != null) setState(() => _radio = r);
                  },
                ),
                if (widget.splitTypes) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: '场景'),
                    items: const [
                      DropdownMenuItem(value: 'FreeRoam', child: Text('漫游')),
                      DropdownMenuItem(value: 'Event', child: Text('比赛')),
                    ],
                    onChanged: (t) {
                      if (t != null) setState(() => _type = t);
                    },
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  '新增 ${info.added} 首 · 分配后 ${info.total} / ${info.limit == 4096 ? '扩容' : info.limit} 首',
                  style: RmText.sans(12, color: exceeds ? rm.danger : rm.fg2),
                ),
                const SizedBox(height: 8),
                Text(
                  exceeds
                      ? '超过电台容量，请减少选择或更换电台；本次不会部分分配。'
                      : (info.added == 0
                            ? '这些歌曲已在目标电台，无需重复分配。'
                            : '按列表顺序追加，保留其他电台的分配；目标已有歌曲不重复添加。'),
                  style: RmText.sans(11.5, color: rm.fg3),
                ),
                if (info.replacesBuiltin) ...[
                  const SizedBox(height: 10),
                  Text(
                    '该电台将由原版切换为自建曲目。',
                    style: RmText.sans(11.5, color: rm.warn),
                  ),
                ],
                const SizedBox(height: 14),
                for (final t in widget.tracks.take(6))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '${t.title} · ${t.artist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RmText.sans(11.5, color: rm.fg3),
                    ),
                  ),
                if (widget.tracks.length > 6)
                  Text(
                    '另有 ${widget.tracks.length - 6} 首',
                    style: RmText.sans(11.5, color: rm.fg3),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          RmButton(label: '取消', onPressed: () => Navigator.pop(context)),
          RmButton(
            key: const ValueKey('batch-assign-confirm'),
            label: info.replacesBuiltin ? '切换并分配' : '分配',
            variant: RmButtonVariant.primary,
            onPressed: exceeds || info.added == 0
                ? null
                : () => Navigator.pop(context, (
                    radio: radio.code,
                    type: _type,
                    limit: info.limit,
                  )),
          ),
        ],
      ),
    );
  }
}
