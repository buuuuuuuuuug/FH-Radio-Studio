import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playlist_plan.dart';
import '../../domain/radio_library.dart';
import '../../state/studio_state.dart';
import '../../state/custom_pool_tracks.dart';
import '../../state/playlist_catalog_state.dart';
import '../../state/playlist_plan_state.dart';

enum PlaylistMode { freeroam, event }

@immutable
class PlaylistState {
  const PlaylistState({
    required this.pool,
    required this.mode,
    required this.search,
    required this.splitPlaylistTypes,
  });

  final List<PoolTrack> pool;
  final PlaylistMode mode;
  final String search;
  final bool splitPlaylistTypes;

  List<PoolTrack> tracksOfRadio(
    String radioCode,
    String playlistType,
    PlaylistPlan plan,
  ) {
    final bySource = {
      for (final track in pool)
        PlaylistAssignment.keyForPath(track.source): track,
    };
    final out = <PoolTrack>[];
    for (final assignment in plan.assignmentsForRadio(
      radioCode,
      playlistType,
    )) {
      final track =
          bySource[assignment.trackKey] ??
          _poolTrackForSource(pool, assignment.source);
      if (track == null) continue;
      out.add(
        track.copyWith(assignedTo: assignment.radioCode, slot: assignment.slot),
      );
    }
    return out;
  }

  List<PoolTrack> poolForDisplay(PlaylistPlan plan) {
    // Resolve assignments once. Repeating assignmentForPath for every song
    // previously normalized and sorted the entire plan for each pool row.
    final ordered = plan.assignments.values.where((a) => a.isAssigned).toList()
      ..sort((a, b) {
        final radio = a.radioCode.compareTo(b.radioCode);
        if (radio != 0) return radio;
        final type = (a.playlistType == 'FreeRoam' ? 0 : 1).compareTo(
          b.playlistType == 'FreeRoam' ? 0 : 1,
        );
        if (type != 0) return type;
        final slot = a.slot.compareTo(b.slot);
        return slot != 0
            ? slot
            : a.source.toLowerCase().compareTo(b.source.toLowerCase());
      });
    final firstBySource = <String, PlaylistAssignment>{};
    for (final assignment in ordered) {
      if (assignment.trackKey.isNotEmpty) {
        firstBySource.putIfAbsent(assignment.trackKey, () => assignment);
      }
      firstBySource.putIfAbsent(
        PlaylistAssignment.keyForPath(assignment.source),
        () => assignment,
      );
    }
    PoolTrack withAssignment(PoolTrack track) {
      final assignment =
          firstBySource[PlaylistAssignment.keyForPath(track.source)];
      return assignment == null
          ? track.copyWith(clearAssigned: true)
          : track.copyWith(
              assignedTo: assignment.radioCode,
              slot: assignment.slot,
            );
    }

    final assignedTrackKeys = _assignedTrackKeys(plan);
    final indexed = <({int index, PoolTrack track})>[
      for (var index = 0; index < pool.length; index += 1)
        (index: index, track: pool[index]),
    ];
    indexed.sort((a, b) {
      final aAssigned = assignedTrackKeys.contains(
        PlaylistAssignment.keyForPath(a.track.source),
      );
      final bAssigned = assignedTrackKeys.contains(
        PlaylistAssignment.keyForPath(b.track.source),
      );
      if (aAssigned != bAssigned) return aAssigned ? 1 : -1;
      final byCompleteness = _configurationCompleteness(
        b.track,
      ).compareTo(_configurationCompleteness(a.track));
      if (byCompleteness != 0) return byCompleteness;
      if (a.track.configured != b.track.configured) {
        return a.track.configured ? -1 : 1;
      }
      if (a.track.isSiren != b.track.isSiren) {
        return a.track.isSiren ? -1 : 1;
      }
      return a.index.compareTo(b.index);
    });
    return [for (final item in indexed) withAssignment(item.track)];
  }

  PlaylistState copyWith({
    List<PoolTrack>? pool,
    PlaylistMode? mode,
    String? search,
    bool? splitPlaylistTypes,
  }) {
    return PlaylistState(
      pool: pool ?? this.pool,
      mode: mode ?? this.mode,
      search: search ?? this.search,
      splitPlaylistTypes: splitPlaylistTypes ?? this.splitPlaylistTypes,
    );
  }
}

Set<String> _assignedTrackKeys(PlaylistPlan plan) {
  final keys = <String>{};
  for (final assignment in plan.assignments.values) {
    if (!assignment.isAssigned) continue;
    if (assignment.trackKey.isNotEmpty) keys.add(assignment.trackKey);
    if (assignment.source.trim().isNotEmpty) {
      keys.add(PlaylistAssignment.keyForPath(assignment.source));
    }
  }
  return keys;
}

PoolTrack? _poolTrackForSource(List<PoolTrack> pool, String source) {
  for (final item in pool) {
    if (item.source == source ||
        PlaylistAssignment.keyForPath(item.source) ==
            PlaylistAssignment.keyForPath(source)) {
      return item;
    }
  }
  return null;
}

class PlaylistNotifier extends StateNotifier<PlaylistState> {
  PlaylistNotifier(this.ref, List<PoolTrack> pool)
    : super(
        PlaylistState(
          pool: List<PoolTrack>.from(pool),
          mode: PlaylistMode.freeroam,
          search: '',
          splitPlaylistTypes: false,
        ),
      );

  final Ref ref;

  void setMode(PlaylistMode m) => state = state.copyWith(mode: m);
  void setSearch(String s) => state = state.copyWith(search: s);
  void setSplitPlaylistTypes(bool value) {
    if (_editingLocked) return;
    state = state.copyWith(splitPlaylistTypes: value);
  }

  void setPool(List<PoolTrack> pool) {
    state = state.copyWith(pool: List<PoolTrack>.from(pool));
  }

  void reorder(
    String source,
    String beforeSource,
    String radioCode,
    String type,
  ) => ref
      .read(playlistPlanProvider.notifier)
      .transaction(() => _reorder(source, beforeSource, radioCode, type));

  void _reorder(
    String source,
    String beforeSource,
    String radioCode,
    String type,
  ) {
    if (_editingLocked || source == beforeSource) return;
    var plan = _ensureEditablePlanSeeded().moveBefore(
      source: source,
      beforeSource: beforeSource,
      radioCode: radioCode,
      playlistType: type,
    );
    if (!state.splitPlaylistTypes) plan = plan.syncPlaylistTypesFrom(type);
    ref.read(playlistPlanProvider.notifier).replaceWith(plan);
  }

  /// 把曲目分配到电台。slot 自动 = 该电台当前已分配数 + 1。
  bool assignToRadio(
    String trackId,
    String radioCode,
    String playlistType, {
    int? maxSlots,
    String? originRadioCode,
    String? originPlaylistType,
  }) => ref
      .read(playlistPlanProvider.notifier)
      .transaction(
        () => _assignToRadio(
          trackId,
          radioCode,
          playlistType,
          maxSlots: maxSlots,
          originRadioCode: originRadioCode,
          originPlaylistType: originPlaylistType,
        ),
      );

  bool _assignToRadio(
    String trackId,
    String radioCode,
    String playlistType, {
    int? maxSlots,
    String? originRadioCode,
    String? originPlaylistType,
  }) {
    if (_editingLocked) return false;
    final track = _trackById(trackId);
    if (track == null) return false;
    final targetRadio = radioCode.trim().toUpperCase();
    final targetType = PlaylistAssignment.normalizePlaylistType(playlistType);
    var plan = _editablePlan();
    if (!state.splitPlaylistTypes) {
      plan = plan.syncPlaylistTypesFrom(targetType);
    }
    final existing =
        plan.assignmentFor(
          source: track.source,
          radioCode: targetRadio,
          playlistType: targetType,
        ) ??
        (!state.splitPlaylistTypes
            ? plan.assignmentFor(
                source: track.source,
                radioCode: targetRadio,
                playlistType: _otherPlaylistType(targetType),
              )
            : null);
    if (existing == null &&
        maxSlots != null &&
        (!plan.canFitRadioSources(targetRadio, [track.source], maxSlots) ||
            plan.assignmentsForRadio(targetRadio, targetType).length >=
                maxSlots)) {
      return false;
    }
    final nextSlot =
        existing?.slot ??
        plan.assignmentsForRadio(targetRadio, targetType).length + 1;
    var nextPlan = plan.assign(
      source: track.source,
      radioCode: targetRadio,
      playlistType: targetType,
      slot: nextSlot,
      projectDir: ref.read(studioProvider).projectDir,
    );
    if (!state.splitPlaylistTypes) {
      nextPlan = nextPlan.assign(
        source: track.source,
        radioCode: targetRadio,
        playlistType: _otherPlaylistType(targetType),
        slot: nextSlot,
        projectDir: ref.read(studioProvider).projectDir,
      );
    }
    nextPlan = _removeMoveOrigin(
      plan: nextPlan,
      source: track.source,
      targetRadioCode: targetRadio,
      targetPlaylistType: targetType,
      originRadioCode: originRadioCode,
      originPlaylistType: originPlaylistType,
    );
    ref.read(playlistPlanProvider.notifier).replaceWith(nextPlan);
    state = state.copyWith(
      pool: [
        for (final t in state.pool)
          if (t.id == trackId)
            t.copyWith(assignedTo: targetRadio, slot: nextSlot)
          else
            t,
      ],
    );
    return true;
  }

  /// Build the entire selection locally; exceeding capacity changes nothing.
  bool assignManyToRadio(
    List<String> trackIds,
    String radioCode,
    String playlistType, {
    required int maxSlots,
  }) {
    if (_editingLocked) return false;
    final tracks = <PoolTrack>[];
    final seen = <String>{};
    for (final id in trackIds) {
      final track = _trackById(id);
      if (track == null) return false;
      if (seen.add(PlaylistAssignment.keyForPath(track.source))) {
        tracks.add(track);
      }
    }
    if (tracks.isEmpty) return false;
    var plan = _editablePlan();
    if (!state.splitPlaylistTypes) {
      plan = plan.syncPlaylistTypesFrom(playlistType);
    }
    final type = PlaylistAssignment.normalizePlaylistType(playlistType);
    final existing = plan.assignmentsForRadio(radioCode, type);
    final newTracks = tracks
        .where(
          (t) =>
              plan.assignmentFor(
                source: t.source,
                radioCode: radioCode,
                playlistType: type,
              ) ==
              null,
        )
        .toList();
    if (existing.length + newTracks.length > maxSlots ||
        !plan.canFitRadioSources(
          radioCode,
          newTracks.map((t) => t.source),
          maxSlots,
        )) {
      return false;
    }
    var slot = existing.length;
    for (final track in newTracks) {
      plan = plan.assign(
        source: track.source,
        radioCode: radioCode,
        playlistType: type,
        slot: ++slot,
        projectDir: ref.read(studioProvider).projectDir,
      );
    }
    if (!state.splitPlaylistTypes) plan = plan.syncPlaylistTypesFrom(type);
    ref.read(playlistPlanProvider.notifier).replaceWith(plan);
    return true;
  }

  PlaylistPlan _removeMoveOrigin({
    required PlaylistPlan plan,
    required String source,
    required String targetRadioCode,
    required String targetPlaylistType,
    required String? originRadioCode,
    required String? originPlaylistType,
  }) {
    final originRadio = originRadioCode?.trim().toUpperCase();
    if (originRadio == null || originRadio.isEmpty) return plan;
    final originType = originPlaylistType == null
        ? null
        : PlaylistAssignment.normalizePlaylistType(originPlaylistType);
    if (state.splitPlaylistTypes) {
      if (originType == null) return plan;
      if (originRadio == targetRadioCode && originType == targetPlaylistType) {
        return plan;
      }
      return plan.unassign(
        source,
        radioCode: originRadio,
        playlistType: originType,
        projectDir: ref.read(studioProvider).projectDir,
      );
    }
    if (originRadio == targetRadioCode) return plan;
    return plan.unassign(
      source,
      radioCode: originRadio,
      projectDir: ref.read(studioProvider).projectDir,
    );
  }

  /// 把曲目移回池子（取消分配）。
  void unassign(String trackId, {String? radioCode, String? playlistType}) =>
      ref
          .read(playlistPlanProvider.notifier)
          .transaction(
            () => _unassign(
              trackId,
              radioCode: radioCode,
              playlistType: playlistType,
            ),
          );

  void _unassign(String trackId, {String? radioCode, String? playlistType}) {
    if (_editingLocked) return;
    final track = _trackById(trackId);
    if (track == null) return;
    if (!state.splitPlaylistTypes && playlistType != null) {
      _syncPlanFrom(playlistType);
    } else {
      _ensureEditablePlanSeeded();
    }
    ref
        .read(playlistPlanProvider.notifier)
        .unassign(
          track.source,
          radioCode: radioCode,
          playlistType: state.splitPlaylistTypes ? playlistType : null,
        );
    state = state.copyWith(
      pool: [
        for (final t in state.pool)
          if (t.id == trackId) t.copyWith(clearAssigned: true) else t,
      ],
    );
  }

  void restoreBuiltin(String radioCode, String playlistType) => ref
      .read(playlistPlanProvider.notifier)
      .transaction(() => _restoreBuiltin(radioCode, playlistType));

  void _restoreBuiltin(String radioCode, String playlistType) {
    if (_editingLocked) return;
    final controller = ref.read(playlistPlanProvider.notifier);
    _ensureEditablePlanSeeded();
    if (!state.splitPlaylistTypes) {
      _syncPlanFrom(playlistType);
    }
    controller.restoreBuiltin(radioCode: radioCode, playlistType: playlistType);
    if (!state.splitPlaylistTypes) {
      controller.restoreBuiltin(
        radioCode: radioCode,
        playlistType: _otherPlaylistType(playlistType),
      );
    }
    state = state.copyWith(
      pool: [for (final t in state.pool) t.copyWith(clearAssigned: true)],
    );
  }

  int copyGameLayout(PlaylistCatalog catalog) {
    if (_editingLocked) return 0;
    final plan = playlistPlanFromCatalog(
      catalog,
      state.pool,
      projectDir: ref.read(studioProvider).projectDir,
    );
    ref.read(playlistPlanProvider.notifier).replaceWith(plan);
    return plan.assignments.length;
  }

  bool get _editingLocked => ref.read(studioProvider).projectEditingLocked;

  PoolTrack? _trackById(String trackId) {
    for (final track in state.pool) {
      if (track.id == trackId) return track;
    }
    return null;
  }

  void _syncPlanFrom(String playlistType) {
    final plan = _ensureEditablePlanSeeded();
    if (!plan.hasDraft && !plan.hasSplitPlaylistDifferences) return;
    ref
        .read(playlistPlanProvider.notifier)
        .replaceWith(plan.syncPlaylistTypesFrom(playlistType));
  }

  PlaylistPlan _editablePlan() {
    final current = ref.read(playlistPlanProvider);
    if (current.hasDraft ||
        ref.read(playlistPlanProvider.notifier).hasUserPlan) {
      return current;
    }
    final effective = ref.read(effectivePlaylistPlanProvider);
    if (effective.hasDraft) return effective;
    final catalog = ref.read(playlistCatalogProvider);
    if (catalog.failed) return effective;
    return playlistPlanFromCatalog(
      catalog,
      state.pool,
      projectDir: ref.read(studioProvider).projectDir,
      includeBuiltinTargets: false,
    );
  }

  PlaylistPlan _ensureEditablePlanSeeded() {
    final plan = _editablePlan();
    if (!identical(plan, ref.read(playlistPlanProvider)) && plan.hasDraft) {
      ref.read(playlistPlanProvider.notifier).replaceWith(plan);
    }
    return plan;
  }

  String _otherPlaylistType(String playlistType) {
    return PlaylistAssignment.normalizePlaylistType(playlistType) == 'Event'
        ? 'FreeRoam'
        : 'Event';
  }
}

PlaylistPlan playlistPlanFromCatalog(
  PlaylistCatalog catalog,
  List<PoolTrack> pool, {
  String? projectDir,
  bool includeBuiltinTargets = true,
}) {
  var plan = const PlaylistPlan.empty();
  for (final radio in catalog.radios) {
    for (final playlistType in const ['FreeRoam', 'Event']) {
      if (catalog.modeOfList(radio.code, playlistType) != StationMode.custom) {
        if (includeBuiltinTargets) {
          plan = plan.restoreBuiltin(
            radioCode: radio.code,
            playlistType: playlistType,
          );
        }
        continue;
      }

      var slot = 1;
      for (final track in catalog.tracksOfRadio(radio.code, playlistType)) {
        // Source identities are supplied by the catalog's authoritative mapping.
        final source = catalog.sourceForTrack(track);
        if (source == null || source.trim().isEmpty) continue;
        plan = plan.assign(
          source: source,
          radioCode: radio.code,
          playlistType: playlistType,
          slot: slot,
          projectDir: projectDir,
        );
        slot += 1;
      }
    }
  }
  return plan;
}

final playlistProvider = StateNotifierProvider<PlaylistNotifier, PlaylistState>(
  (ref) {
    final notifier = PlaylistNotifier(ref, ref.read(realPoolTracksProvider));
    ref.listen<List<PoolTrack>>(
      realPoolTracksProvider,
      (_, next) => notifier.setPool(next),
    );
    return notifier;
  },
);

int _configurationCompleteness(PoolTrack track) {
  if (track.configured) return 4;
  return track.confirmed.clamp(0, 4).toInt();
}
