import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import 'rm_button.dart';
import 'rm_icon.dart';

/// Compact setting groups shared by import, export and audition dialogs.
class DialogSettingsSection extends StatelessWidget {
  const DialogSettingsSection({
    super.key,
    required this.title,
    required this.child,
  });
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final rm = context.rm;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: rm.border),
        borderRadius: BorderRadius.circular(RmTokens.rMd),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: RmText.sans(12.5, weight: FontWeight.w600, color: rm.fg),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Shared frame and keyboard dismissal for timing import and export.
class TimingDialogFrame extends StatelessWidget {
  const TimingDialogFrame({
    super.key,
    required this.title,
    required this.busy,
    required this.width,
    required this.body,
    required this.actions,
    this.icon,
    this.description,
  });
  final String title;
  final bool busy;
  final double width;
  final Widget body;
  final List<Widget> actions;
  final String? icon;
  final String? description;
  @override
  Widget build(BuildContext context) {
    final rm = context.rm;
    void close() {
      if (!busy) Navigator.of(context).pop();
    }

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(
          primary: rm.accent.base,
          onPrimary: rm.accent.onAccent,
          surface: rm.panel,
        ),
      ),
      child: PopScope(
        canPop: !busy,
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
          child: Focus(
            autofocus: true,
            child: Dialog(
              backgroundColor: rm.panel,
              surfaceTintColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(24),
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(RmTokens.rLg),
                side: BorderSide(color: rm.borderStrong),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: width,
                  maxHeight: MediaQuery.sizeOf(context).height - 64,
                ),
                child: SizedBox(
                  width: width,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
                        child: Row(
                          children: [
                            if (icon != null) ...[
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: rm.accent.bg,
                                  border: Border.all(color: rm.accent.ring),
                                  borderRadius: BorderRadius.circular(
                                    RmTokens.rMd,
                                  ),
                                ),
                                child: Center(
                                  child: RmIcon(
                                    icon!,
                                    size: 17,
                                    color: rm.accent.base,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: RmText.sans(
                                      icon == null ? 15 : 17,
                                      weight: FontWeight.w600,
                                      color: rm.fg,
                                    ),
                                  ),
                                  if (description != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      description!,
                                      style: RmText.sans(11.5, color: rm.fg3),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Text(
                              busy ? '正在处理…' : 'Esc 关闭',
                              style: RmText.mono(10.5, color: rm.fg3),
                            ),
                            const SizedBox(width: 10),
                            RmButton.icon(
                              onPressed: busy ? null : close,
                              icon: Icon(Icons.close, size: 16, color: rm.fg3),
                              tooltip: '关闭',
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: rm.border),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: body,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: rm.border)),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          runSpacing: 6,
                          children: actions,
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
    );
  }
}
