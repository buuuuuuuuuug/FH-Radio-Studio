import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import 'rm_button.dart';

/// Shared frame and keyboard dismissal for timing import and export.
class TimingDialogFrame extends StatelessWidget {
  const TimingDialogFrame({
    super.key,
    required this.title,
    required this.busy,
    required this.width,
    required this.body,
    required this.actions,
  });
  final String title;
  final bool busy;
  final double width;
  final Widget body;
  final List<Widget> actions;
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
                            Expanded(
                              child: Text(
                                title,
                                style: RmText.sans(
                                  15,
                                  weight: FontWeight.w600,
                                  color: rm.fg,
                                ),
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
