import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import 'rm_banner.dart';
import 'rm_button.dart';
import 'timing_dialog_frame.dart';

Future<bool?> showSplitPlaylistConfirmation(BuildContext context) =>
    showDialog<bool>(
      context: context,
      barrierColor: RmTokens.modalBackdrop,
      builder: (context) => TimingDialogFrame(
        title: '分开编辑漫游和比赛？',
        icon: 'list',
        description: '分别安排 FreeRoam 与 Event 播放列表',
        width: 540,
        busy: false,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RmBanner(
              key: ValueKey('split-playlist-enable-warning'),
              kind: RmBannerKind.warn,
              title: '实验功能，当前不推荐使用。',
              body: '分场景排布仍可能存在问题，建议使用统一列表。',
            ),
            const SizedBox(height: 16),
            Text(
              '开启后会显示 FreeRoam 和 Event 两张独立列表。FreeRoam 用于开放世界漫游，Event 用于比赛内播放。',
              style: RmText.body(color: context.rm.fg2),
            ),
            const SizedBox(height: 10),
            Text(
              '关闭时如果两边不一致，需要选择保留哪一张，并用它覆盖另一张。',
              style: RmText.body(color: context.rm.fg3),
            ),
          ],
        ),
        actions: [
          RmButton(
            label: '取消',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          RmButton(
            label: '打开',
            variant: RmButtonVariant.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
