import '../widgets/editor_shortcuts_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/app_state.dart';
import '../widgets/layout_controls.dart';
import '../widgets/custom_accent_dialog.dart';
import '../widgets/rm_button.dart';
import '../state/router.dart';
import '../state/editor_options.dart';
import '../state/siren_import_queue_state.dart';
import '../theme/accents.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';

final settingsExpandedProvider = StateProvider<bool>((ref) => false);

/// 设置入口就地展开，保留原界面和编辑状态。
class TweaksPanel extends ConsumerStatefulWidget {
  const TweaksPanel({super.key, this.embedded = false});
  final bool embedded;

  @override
  ConsumerState<TweaksPanel> createState() => _TweaksPanelState();
}

class _TweaksPanelState extends ConsumerState<TweaksPanel> {
  @override
  Widget build(BuildContext context) {
    final rm = context.rm;
    if (widget.embedded) {
      return Container(
        constraints: BoxConstraints(
          maxHeight:
              (MediaQuery.sizeOf(context).height -
                      (ref.watch(navStyleProvider) == NavStyle.rail
                          ? 240
                          : 120))
                  .clamp(120.0, 640.0),
        ),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: rm.panel,
          border: Border.all(color: rm.border),
          borderRadius: BorderRadius.circular(RmTokens.rSm),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _section(context, '主题', _themeSection(context)),
              _divider(context),
              _section(context, '强调色', _accentSection(context)),
              _divider(context),
              _section(context, '导航布局', _navSection(context)),
              _divider(context),
              _section(context, '界面宽度', const PageWidthControl()),
              _divider(context),
              _section(context, '人工精修窗口宽度', const ManualRefineWidthControl()),
              _divider(context),
              _section(context, '快捷键', const EditorShortcutsButton()),
              _divider(context),
              _section(context, '功能', _sirenSection(context)),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      child: Center(
        child: Container(
          width: 720,
          margin: const EdgeInsets.all(40),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: rm.panel,
            border: Border.all(color: rm.border),
            borderRadius: BorderRadius.circular(RmTokens.rLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('设置', style: RmText.pageH1(color: rm.fg)),
              _section(context, '主题', _themeSection(context)),
              _divider(context),
              _section(context, '强调色', _accentSection(context)),
              _divider(context),
              _section(context, '导航布局', _navSection(context)),
              _divider(context),
              _section(context, '界面宽度', const PageWidthControl()),
              _divider(context),
              _section(context, '人工精修窗口宽度', const ManualRefineWidthControl()),
              _divider(context),
              _section(context, '快捷键', const EditorShortcutsButton()),
              _divider(context),
              _section(context, '跳转', _routeSection(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String label, Widget body) {
    final rm = context.rm;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label.toUpperCase(),
            style: RmText.mono(10.5, color: rm.fg4, letterSpacing: 0.12 * 10.5),
          ),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }

  Widget _sirenSection(BuildContext context) {
    final rm = context.rm;
    final enabled = ref.watch(editorOptionsProvider).sirenEnabled;
    final importing = ref.watch(sirenImportQueueProvider).importing;
    return Row(
      children: [
        Expanded(
          child: Text('启用塞壬唱片', style: RmText.sans(11.5, color: rm.fg2)),
        ),
        Tooltip(
          message: importing ? '导入完成后可切换' : '显示在线唱片库入口',
          child: SizedBox(
            width: 34,
            height: 22,
            child: FittedBox(
              child: Switch(
                value: enabled,
                activeTrackColor: rm.accent.base,
                activeThumbColor: rm.panel,
                inactiveTrackColor: rm.raised,
                inactiveThumbColor: rm.fg4,
                trackOutlineColor: WidgetStateProperty.all(rm.border),
                onChanged: importing
                    ? null
                    : (v) => ref
                          .read(editorOptionsProvider.notifier)
                          .update(sirenEnabled: v),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _divider(BuildContext context) =>
      Container(height: 1, color: context.rm.border);

  Widget _themeSection(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    return Row(
      children: [
        _seg(
          context,
          '浅色',
          mode == ThemeMode.light,
          () => ref.read(themeModeProvider.notifier).set(ThemeMode.light),
        ),
        const SizedBox(width: 6),
        _seg(
          context,
          '深色',
          mode == ThemeMode.dark,
          () => ref.read(themeModeProvider.notifier).set(ThemeMode.dark),
        ),
      ],
    );
  }

  Widget _accentSection(BuildContext context) {
    final accent = ref.watch(accentProvider);
    final custom = ref.watch(customAccentProvider);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final a in AppAccent.values)
          _accentSwatch(context, a, custom == null && a == accent),
        RmButton(
          size: RmButtonSize.sm,
          label: '自选',
          tooltip: '选择任意颜色或输入十六进制颜色',
          leading: Icon(
            Icons.palette_outlined,
            size: 13,
            color: custom ?? context.rm.fg2,
          ),
          onPressed: () async {
            final color = await showDialog<Color>(
              context: context,
              builder: (_) => CustomAccentDialog(
                initial:
                    custom ??
                    accentColors(accent, Theme.of(context).brightness).base,
              ),
            );
            if (color != null && mounted) {
              ref.read(customAccentProvider.notifier).set(color);
            }
          },
        ),
      ],
    );
  }

  Widget _accentSwatch(BuildContext context, AppAccent a, bool active) {
    final rm = context.rm;
    final brightness = Theme.of(context).brightness;
    final color = accentColors(a, brightness).base;
    return GestureDetector(
      onTap: () {
        ref.read(customAccentProvider.notifier).set(null);
        ref.read(accentProvider.notifier).set(a);
      },
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? rm.fg : rm.border,
            width: active ? 2 : 1,
          ),
        ),
      ),
    );
  }

  Widget _navSection(BuildContext context) {
    final style = ref.watch(navStyleProvider);
    return Row(
      children: [
        _seg(
          context,
          '左侧栏',
          style == NavStyle.rail,
          () => ref.read(navStyleProvider.notifier).set(NavStyle.rail),
        ),
        const SizedBox(width: 6),
        _seg(
          context,
          '顶部 tab',
          style == NavStyle.tabs,
          () => ref.read(navStyleProvider.notifier).set(NavStyle.tabs),
        ),
      ],
    );
  }

  Widget _routeSection(BuildContext context) {
    final routes = [
      ('概览', RmRoutes.dashboard),
      ('塞壬', RmRoutes.siren),
      ('池子', RmRoutes.pool),
      ('播放列表', RmRoutes.playlist),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final r in routes)
          _seg(context, r.$1, false, () => context.go(r.$2)),
      ],
    );
  }

  Widget _seg(
    BuildContext context,
    String label,
    bool active,
    VoidCallback onTap,
  ) {
    final rm = context.rm;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? rm.accent.bg : rm.raised,
          border: Border.all(color: active ? rm.accent.ring : rm.border),
          borderRadius: BorderRadius.circular(RmTokens.rSm),
        ),
        child: Text(
          label,
          style: RmText.sans(
            11.5,
            color: active ? rm.accent.base : rm.fg2,
            weight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
