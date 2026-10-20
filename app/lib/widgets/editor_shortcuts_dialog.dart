import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/editor_shortcuts.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import 'rm_button.dart';

class EditorShortcutsButton extends StatelessWidget {
  const EditorShortcutsButton({super.key});
  @override
  Widget build(BuildContext context) => RmButton(
    label: '修改快捷键',
    size: RmButtonSize.sm,
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => const _ShortcutDialog(),
    ),
  );
}

class _ShortcutDialog extends ConsumerStatefulWidget {
  const _ShortcutDialog();
  @override
  ConsumerState<_ShortcutDialog> createState() => _ShortcutDialogState();
}

class _ShortcutDialogState extends ConsumerState<_ShortcutDialog> {
  late Map<EditorAction, EditorChord> draft;
  EditorAction? recording;
  bool recordingModifier = false;
  String? error;
  late String modifier;
  final focus = FocusNode();
  @override
  void initState() {
    super.initState();
    draft = {...ref.read(editorShortcutsProvider)};
    modifier = readLoopModifier(
      ref.read(editorShortcutsProvider.notifier).prefs,
    );
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rm = context.rm;
    return Focus(
      focusNode: focus,
      autofocus: true,
      onKeyEvent: (_, event) {
        if ((!recordingModifier && recording == null) ||
            event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          setState(() {
            recording = null;
            recordingModifier = false;
          });
          return KeyEventResult.handled;
        }
        if (recordingModifier) {
          final selected = loopModifierForKey(event.logicalKey);
          final next = {...draft};
          for (final a in loopNudgeActions) {
            next[a] = withLoopModifier(next[baseNudgeAction(a)]!, selected);
          }
          setState(() {
            modifier = selected;
            draft = next;
            error = shortcutConflict(next);
            recordingModifier = false;
          });
          return KeyEventResult.handled;
        }
        final h = HardwareKeyboard.instance;
        if (modifierKey(event.logicalKey) &&
            (recording != EditorAction.toggleSnap ||
                [
                      h.isControlPressed,
                      h.isShiftPressed,
                      h.isAltPressed,
                      h.isMetaPressed,
                    ].where((v) => v).length <
                    2)) {
          return KeyEventResult.handled;
        }
        final combo = EditorChord(
          event.logicalKey,
          ctrl: h.isControlPressed,
          shift: h.isShiftPressed,
          alt: h.isAltPressed,
          meta: h.isMetaPressed,
        );
        final next = {...draft, recording!: combo};
        for (final a in loopNudgeActions) {
          next[a] = withLoopModifier(next[baseNudgeAction(a)]!, modifier);
        }
        final problem = shortcutConflict(next);
        setState(() {
          error = problem;
          draft = next;
          if (problem == null) {
            recording = null;
          }
        });
        return KeyEventResult.handled;
      },
      child: Dialog(
        backgroundColor: rm.panel,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 620,
            maxHeight: MediaQuery.sizeOf(context).height - 80,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('自定义快捷键', style: RmText.modalH2(color: rm.fg)),
                const SizedBox(height: 8),
                Text(
                  '点击右侧按键后重新录入。两端同移只设置一个组合键，按住它并使用原微调键；Esc 取消录入或返回。',
                  style: RmText.sans(11.5, color: rm.fg3),
                ),
                const SizedBox(height: 10),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      error!,
                      style: RmText.sans(11.5, color: rm.warn),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '两端同移组合键',
                        style: RmText.sans(12, color: rm.fg2),
                      ),
                    ),
                    RmButton(
                      key: const ValueKey('shortcut-loop-modifier'),
                      label: recordingModifier
                          ? '请按一个键…'
                          : loopModifierLabel(modifier),
                      variant: recordingModifier
                          ? RmButtonVariant.primary
                          : RmButtonVariant.defaultBtn,
                      size: RmButtonSize.sm,
                      onPressed: () {
                        setState(() {
                          recording = null;
                          recordingModifier = true;
                          error = null;
                        });
                        focus.requestFocus();
                      },
                    ),
                  ],
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: editorActionOrder.length,
                    itemBuilder: (context, i) {
                      final a = editorActionOrder[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                editorActionLabel(a),
                                style: RmText.sans(12, color: rm.fg2),
                              ),
                            ),
                            RmButton(
                              size: RmButtonSize.sm,
                              key: ValueKey('shortcut-${a.name}'),
                              label: recording == a
                                  ? '请按组合键…'
                                  : draft[a]!.label,
                              variant: recording == a
                                  ? RmButtonVariant.primary
                                  : RmButtonVariant.defaultBtn,
                              onPressed: () {
                                setState(() {
                                  recordingModifier = false;
                                  recording = a;
                                  error = null;
                                });
                                focus.requestFocus();
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    RmButton(
                      label: '恢复默认',
                      onPressed: () => setState(() {
                        draft = defaultEditorShortcuts();
                        modifier = 'Alt';
                        recordingModifier = false;
                        recording = null;
                        error = null;
                      }),
                    ),
                    RmButton(
                      label: '取消',
                      onPressed: () => Navigator.pop(context),
                    ),
                    RmButton(
                      label: '保存',
                      variant: RmButtonVariant.primary,
                      onPressed:
                          recordingModifier ||
                              recording != null ||
                              error != null
                          ? null
                          : () {
                              final ctl = ref.read(
                                editorShortcutsProvider.notifier,
                              );
                              ctl.save(draft, loopModifier: modifier);
                              Navigator.pop(context);
                            },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
