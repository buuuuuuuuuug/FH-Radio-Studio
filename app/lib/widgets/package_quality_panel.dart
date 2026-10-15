import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';

/// Size curves are produced by the CLI; this widget only presents the selected quality.
class PackageBuildDialogFrame extends StatefulWidget {
  const PackageBuildDialogFrame({
    super.key,
    required this.child,
    this.estimate,
    this.onQualityChanged,
  });
  final Widget child;
  final Future<Map<String, dynamic>>? estimate;
  final ValueChanged<int>? onQualityChanged;
  @override
  State<PackageBuildDialogFrame> createState() =>
      _PackageBuildDialogFrameState();
}

class _PackageBuildDialogFrameState extends State<PackageBuildDialogFrame> {
  int quality = 50;
  @override
  Widget build(BuildContext context) {
    final rm = context.rm;
    final expanded = widget.estimate != null || widget.onQualityChanged != null;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      child: SizedBox(
        width: expanded ? 1040 : 640,
        child: SingleChildScrollView(
          child: LayoutBuilder(
            builder: (context, c) {
              if (!expanded) return widget.child;
              final panel = Container(
                decoration: BoxDecoration(
                  border: c.maxWidth >= 900
                      ? Border(left: BorderSide(color: rm.border))
                      : Border(top: BorderSide(color: rm.border)),
                ),
                padding: const EdgeInsets.all(20),
                child: _qualityPanel(context),
              );
              return Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: rm.panel,
                  border: Border.all(color: rm.borderStrong),
                  borderRadius: BorderRadius.circular(RmTokens.rXl),
                  boxShadow: RmTokens.modal,
                ),
                child: c.maxWidth >= 900
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: widget.child),
                          SizedBox(width: 340, child: panel),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [widget.child, panel],
                      ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _qualityPanel(BuildContext context) {
    final rm = context.rm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '构建质量',
          style: RmText.sans(15, weight: FontWeight.w600, color: rm.fg),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Vorbis · 1–100',
                style: RmText.sans(11.5, color: rm.fg3),
              ),
            ),
            Text(
              '$quality',
              key: const ValueKey('package-quality-value'),
              style: RmText.mono(
                18,
                weight: FontWeight.w600,
                color: rm.accent.base,
              ),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, c) => Stack(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                ),
                child: Slider(
                  key: const ValueKey('package-quality-slider'),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  value: quality.toDouble(),
                  min: 1,
                  max: 100,
                  divisions: 99,
                  activeColor: rm.accent.base,
                  label: '$quality',
                  onChanged: (v) {
                    setState(() => quality = v.round());
                    widget.onQualityChanged?.call(quality);
                  },
                ),
              ),
              Positioned(
                left: 12 + (c.maxWidth - 24) * 49 / 99 - 2,
                top: 19,
                child: IgnorePointer(
                  child: Container(
                    key: const ValueKey('package-default-marker'),
                    width: 4,
                    height: 10,
                    decoration: BoxDecoration(
                      color: rm.accent.base,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('package-quality-default'),
            onPressed: () {
              setState(() => quality = 50);
              widget.onQualityChanged?.call(50);
            },
            child: Text(
              '默认 50',
              style: RmText.sans(
                11,
                color: rm.accent.base,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Text('默认 50；数值越高，体积通常越大。', style: RmText.sans(11, color: rm.fg3)),
        const SizedBox(height: 16),
        FutureBuilder<Map<String, dynamic>>(
          future: widget.estimate,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                '大小预估暂不可用：${snapshot.error}\n仍可构建，实际 bank 大小会在构建时检查。',
                style: RmText.sans(11, color: rm.warn),
              );
            }
            final data = snapshot.data;
            if (data == null) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('正在读取文件与曲目时长…'),
                  ],
                ),
              );
            }
            final rows = (data['files'] as List? ?? const [])
                .whereType<Map>()
                .where(
                  (row) =>
                      row['rebuilt'] == true ||
                      row['primary_radio_bank'] == true,
                )
                .toList();
            num size(Map row, String field) =>
                (row[field] as List)[quality - 1] as num;
            final tooLarge = rows
                .where(
                  (row) =>
                      row['limit_bytes'] is num &&
                      size(row, 'sizes') >= (row['limit_bytes'] as num),
                )
                .toList();
            final nearLimit = rows
                .where(
                  (row) =>
                      row['limit_bytes'] is num &&
                      size(row, 'upper_sizes') >= (row['limit_bytes'] as num),
                )
                .toList();
            final total = rows.fold<num>(
              0,
              (sum, row) => sum + size(row, 'sizes'),
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '电台文件合计',
                        style: RmText.sans(12, color: rm.fg2),
                      ),
                    ),
                    Text(
                      _bytes(total),
                      key: const ValueKey('package-total-estimate'),
                      style: RmText.mono(
                        14,
                        weight: FontWeight.w600,
                        color: rm.fg,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (tooLarge.isNotEmpty || nearLimit.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      tooLarge.isNotEmpty
                          ? '警告：${tooLarge.length} 个 bank 预计达到或超过 2 GiB，需降低质量或减少歌曲。'
                          : '注意：${nearLimit.length} 个 bank 的预留体积接近 2 GiB，请降低质量并检查实际结果。',
                      key: const ValueKey('package-size-warning'),
                      style: RmText.sans(11, color: rm.warn),
                    ),
                  ),
                Container(
                  height: 260,
                  decoration: BoxDecoration(
                    border: Border.all(color: rm.border),
                    borderRadius: BorderRadius.circular(RmTokens.rSm),
                  ),
                  child: ListView.separated(
                    key: const ValueKey('package-file-estimates'),
                    padding: const EdgeInsets.all(10),
                    itemCount: rows.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 9),
                    itemBuilder: (context, i) {
                      final row = rows[i];
                      final name = '${row['name']}';
                      final warning =
                          row['limit_bytes'] is num &&
                          size(row, 'upper_sizes') >=
                              (row['limit_bytes'] as num);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Tooltip(
                              message: name,
                              child: Text(
                                name.split('/').last,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: RmText.sans(10.5, color: rm.fg2),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${row['rebuilt'] == true ? '≈ ' : ''}${_bytes(size(row, 'sizes'))}',
                            style: RmText.mono(
                              10.5,
                              color: warning ? rm.warn : rm.fg3,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'bank 须小于 2 GiB。大小为可变码率估算，警告按额外 45% 余量计算；实际以构建结果为准。',
                  style: RmText.sans(10.5, color: rm.fg3),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  String _bytes(num bytes) => bytes >= 1024 * 1024 * 1024
      ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}
