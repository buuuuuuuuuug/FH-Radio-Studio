import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import '../widgets/rm_button.dart';

enum UnsavedChoice { save, discard }

class PendingEdit {
  PendingEdit({
    required this.label,
    required this.dirty,
    required this.save,
    required this.discard,
  });
  final String label;
  final bool Function() dirty;
  final FutureOr<void> Function() save;
  final void Function() discard;
}

class UnsavedEdits {
  final entries = <String, PendingEdit>{};
  Future<bool>? _pending;
  bool get isDirty => entries.values.any((e) => e.dirty());
  Future<bool> confirm(
    BuildContext context, {
    String? key,
    bool exiting = false,
    bool switching = false,
  }) {
    return _pending ??= _confirm(
      context,
      key: key,
      exiting: exiting,
      switching: switching,
    ).whenComplete(() => _pending = null);
  }

  Future<bool> _confirm(
    BuildContext context, {
    String? key,
    required bool exiting,
    required bool switching,
  }) async {
    final edits = [
      for (final e in entries.entries)
        if ((key == null || e.key == key) && e.value.dirty()) e.value,
    ];
    if (edits.isEmpty) return true;
    final choice = await showDialog<UnsavedChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.rm.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RmTokens.rLg),
          side: BorderSide(color: ctx.rm.border),
        ),
        title: Text(
          exiting ? '关闭前保存修改？' : (switching ? '切换歌曲前保存修改？' : '存在未保存的修改'),
          style: RmText.sans(15, weight: FontWeight.w600, color: ctx.rm.fg),
        ),
        content: Text(
          '${edits.map((e) => e.label).join('、')}尚未保存。',
          style: RmText.sans(12.5, color: ctx.rm.fg3),
        ),
        actions: [
          RmButton(
            onPressed: () => Navigator.pop(ctx),
            label: exiting ? '取消关闭' : (switching ? '取消切换' : '取消返回'),
          ),
          RmButton(
            onPressed: () => Navigator.pop(ctx, UnsavedChoice.discard),
            label: '放弃更改',
          ),
          RmButton(
            variant: RmButtonVariant.primary,
            onPressed: () => Navigator.pop(ctx, UnsavedChoice.save),
            label: exiting ? '保存并关闭' : (switching ? '保存并切换' : '保存并返回'),
          ),
        ],
      ),
    );
    if (choice == null) return false;
    try {
      for (final edit in edits) {
        if (choice == UnsavedChoice.save) {
          await edit.save();
        } else {
          edit.discard();
        }
      }
      return true;
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
      return false;
    }
  }
}

final unsavedEditsProvider = Provider<UnsavedEdits>((ref) => UnsavedEdits());
