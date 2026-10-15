import 'package:flutter/material.dart';
import '../core/song_browse.dart';
import '../theme/app_theme.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import 'rm_button.dart';
import 'rm_icon.dart';
import 'rm_field.dart';

class SongBrowseControls extends StatelessWidget {
  const SongBrowseControls({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
    this.showStatus = true,
    this.showSearch = true,
  });
  final SongBrowse value;
  final ValueChanged<SongBrowse> onChanged;
  final bool compact, showStatus, showSearch;

  Widget _select<T>(
    BuildContext context,
    T current,
    List<(T, String)> items,
    ValueChanged<T> change,
    String tooltip,
  ) {
    final rm = context.rm;
    return Tooltip(
      message: '$tooltip：${items.firstWhere((item) => item.$1 == current).$2}',
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: rm.raised,
          border: Border.all(color: rm.border),
          borderRadius: BorderRadius.circular(RmTokens.rSm),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: current,
            isExpanded: true,
            isDense: true,
            dropdownColor: rm.panel,
            borderRadius: BorderRadius.circular(RmTokens.rSm),
            style: RmText.sans(12, color: rm.fg),
            icon: Icon(Icons.expand_more, size: 14, color: rm.fg3),
            items: [
              for (final item in items)
                DropdownMenuItem(
                  value: item.$1,
                  child: Text(
                    item.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) change(v);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rm = context.rm;
    final sort = _select(
      context,
      value.sort == SongSort.artist
          ? SongSort.editor
          : value.sort == SongSort.modifiedNewest
          ? SongSort.modifiedOldest
          : value.sort,
      const [
        (SongSort.editor, '编辑器顺序（默认按歌手）'),
        (SongSort.title, '歌曲名称'),
        (SongSort.modifiedOldest, '修改日期'),
      ],
      (v) => onChanged(value.copyWith(sort: v)),
      '排序方式',
    );
    final direction = RmButton(
      label: value.descending ? '倒序' : '正序',
      leading: RmIcon(
        value.descending ? 'chevron-down' : 'chevron-up',
        size: 12,
      ),
      tooltip: '切换正序 / 倒序',
      onPressed: () => onChanged(value.copyWith(descending: !value.descending)),
    );
    final filter = _select(
      context,
      value.filter,
      [
        for (final f in SongFilter.values)
          (
            f,
            switch (f) {
              SongFilter.all => '全部状态',
              SongFilter.configured => '已配置',
              SongFilter.unconfigured => '待配置',
              SongFilter.assigned => '已分配',
              SongFilter.unassigned => '未分配',
              SongFilter.duplicates => '可能重复',
            },
          ),
      ],
      (v) => onChanged(value.copyWith(filter: v)),
      '过滤歌曲',
    );
    final station = _select(
      context,
      value.station,
      [('', '全部电台'), for (var i = 1; i <= 9; i++) ('R$i', '电台 $i')],
      (v) => onChanged(value.copyWith(station: v)),
      '按电台过滤',
    );
    final search = SizedBox(
      height: 32,
      child: TextFormField(
        initialValue: value.search,
        style: RmText.sans(12, color: rm.fg),
        cursorColor: rm.accent.base,
        decoration: rmFieldDecoration(
          context,
          hint: '搜索歌曲 / 歌手 / 文件名',
          prefix: Icon(Icons.search, size: 14, color: rm.fg3),
        ),
        onChanged: (v) => onChanged(value.copyWith(search: v)),
      ),
    );
    return Padding(
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 4, 12, 6)
          : const EdgeInsets.all(12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: compact
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showSearch) ...[search, const SizedBox(height: 4)],
                  Row(
                    children: [
                      Expanded(child: sort),
                      const SizedBox(width: 6),
                      SizedBox(width: 84, child: direction),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (showStatus) ...[
                        Expanded(child: filter),
                        const SizedBox(width: 6),
                      ],
                      Expanded(child: station),
                    ],
                  ),
                ],
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 700) {
                    return Row(
                      children: [
                        if (showSearch) ...[
                          Expanded(flex: 4, child: search),
                          const SizedBox(width: 8),
                        ],
                        Expanded(flex: 3, child: sort),
                        const SizedBox(width: 8),
                        SizedBox(width: 84, child: direction),
                        const SizedBox(width: 8),
                        if (showStatus) ...[
                          Expanded(flex: 2, child: filter),
                          const SizedBox(width: 8),
                        ],
                        Expanded(flex: 2, child: station),
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showSearch) ...[search, const SizedBox(height: 8)],
                      Row(
                        children: [
                          Expanded(child: sort),
                          const SizedBox(width: 8),
                          SizedBox(width: 84, child: direction),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (showStatus) ...[
                            Expanded(child: filter),
                            const SizedBox(width: 8),
                          ],
                          Expanded(child: station),
                        ],
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
