class SongSelection {
  SongSelection({Set<String>? ids, this.anchor}) : ids = {...?ids};
  final Set<String> ids;
  final String? anchor;
  SongSelection click(String id, List<String> visible, {bool range = false}) {
    final next = {...ids};
    final from = visible.indexOf(anchor ?? id);
    final to = visible.indexOf(id);
    if (range && from >= 0 && to >= 0) {
      next.addAll(
        visible.sublist(from < to ? from : to, (from > to ? from : to) + 1),
      );
    } else if (!next.remove(id)) {
      next.add(id);
    }
    return SongSelection(ids: next, anchor: id);
  }
}
