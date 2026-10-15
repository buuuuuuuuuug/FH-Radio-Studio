import '../domain/radio_library.dart';

String formatSongModifiedMinute(DateTime? date) {
  if (date == null) return '—';
  final t = date.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

enum SongSort { editor, modifiedNewest, modifiedOldest, artist, title }

enum SongFilter {
  all,
  configured,
  unconfigured,
  assigned,
  unassigned,
  duplicates,
}

class SongBrowse {
  const SongBrowse({
    this.search = '',
    this.sort = SongSort.editor,
    this.filter = SongFilter.all,
    this.station = '',
    this.descending = false,
  });
  final String search;
  final SongSort sort;
  final SongFilter filter;
  final String station;
  final bool descending;
  SongBrowse copyWith({
    String? search,
    SongSort? sort,
    SongFilter? filter,
    String? station,
    bool? descending,
  }) => SongBrowse(
    search: search ?? this.search,
    sort: sort ?? this.sort,
    filter: filter ?? this.filter,
    station: station ?? this.station,
    descending: descending ?? this.descending,
  );
}

String songIdentity(PoolTrack t) =>
    '${t.title.trim().toLowerCase()}|${t.artist.trim().toLowerCase()}|${t.durationSec.round()}';
Set<String> duplicateSongs(List<PoolTrack> tracks) {
  final counts = <String, int>{};
  for (final t in tracks) {
    final key = songIdentity(t);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return {
    for (final e in counts.entries)
      if (e.value > 1) e.key,
  };
}

List<PoolTrack> browseSongs(
  List<PoolTrack> all,
  SongBrowse options, {
  Set<String>? duplicates,
}) {
  final repeated = duplicates ?? duplicateSongs(all);
  final q = options.search.trim().toLowerCase();
  final result = all
      .where(
        (t) =>
            (q.isEmpty ||
                '${t.title} ${t.artist} ${t.source}'.toLowerCase().contains(
                  q,
                )) &&
            (options.station.isEmpty || t.assignedTo == options.station) &&
            switch (options.filter) {
              SongFilter.all => true,
              SongFilter.configured => t.configured,
              SongFilter.unconfigured => !t.configured,
              SongFilter.assigned => t.assignedTo != null,
              SongFilter.unassigned => t.assignedTo == null,
              SongFilter.duplicates => repeated.contains(songIdentity(t)),
            },
      )
      .toList();
  if (options.sort != SongSort.editor) {
    result.sort((a, b) {
      final value = switch (options.sort) {
        SongSort.modifiedNewest => (b.modifiedAt ?? DateTime(1970)).compareTo(
          a.modifiedAt ?? DateTime(1970),
        ),
        SongSort.modifiedOldest => (a.modifiedAt ?? DateTime(1970)).compareTo(
          b.modifiedAt ?? DateTime(1970),
        ),
        SongSort.artist => a.artist.toLowerCase().compareTo(
          b.artist.toLowerCase(),
        ),
        SongSort.title => a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        ),
        SongSort.editor => 0,
      };
      return value != 0
          ? value
          : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
  }
  return options.descending ? result.reversed.toList() : result;
}
