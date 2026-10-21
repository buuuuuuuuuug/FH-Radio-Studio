import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/playlist_plan.dart';
import 'rm_banner.dart';

class CrossRadioAssignmentNotice extends StatelessWidget {
  const CrossRadioAssignmentNotice({
    super.key,
    required this.plan,
    this.titleForSource,
  });
  final PlaylistPlan plan;
  final String Function(String)? titleForSource;

  @override
  Widget build(BuildContext context) {
    final groups = plan.crossRadioAssignments.values.toList();
    if (groups.isEmpty) return const SizedBox.shrink();
    final details = groups.map((items) {
      final source = items.first.source;
      final radios = items.map((a) => a.radioCode).toSet().toList()..sort();
      return '${titleForSource?.call(source) ?? p.basename(source)}：${radios.join(' / ')}';
    }).toList();
    return Tooltip(
      message: details.join('\n'),
      child: RmBanner(
        key: const ValueKey('cross-radio-assignment-notice'),
        kind: RmBannerKind.warn,
        title: '${groups.length} 首歌曲分配到多个电台',
        body:
            '${details.take(3).join('；')}${details.length > 3 ? ' 等' : ''}。每个电台会分别收录，增加准备包体积。若只是更换电台，请移除原分配。',
      ),
    );
  }
}
