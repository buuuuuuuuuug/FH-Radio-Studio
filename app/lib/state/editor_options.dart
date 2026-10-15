import 'playlist_catalog_state.dart';
import 'playlist_plan_state.dart';
import '../domain/radio_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/project_workspace.dart';
import 'studio_state.dart';

class EditorOptions {
  const EditorOptions({
    this.syncPostLoop = false,
    this.manualOnly = false,
    this.sirenEnabled = false,
    this.expansionEnabled = false,
    this.slmEnabled = false,
  });
  final bool syncPostLoop;
  final bool manualOnly;
  final bool sirenEnabled;
  final bool expansionEnabled;
  final bool slmEnabled;
}

class EditorOptionsController extends StateNotifier<EditorOptions> {
  EditorOptionsController(this.ref) : super(const EditorOptions()) {
    _load();
    ref.listen<String>(
      studioProvider.select((s) => s.projectDir),
      (_, next) => _load(),
    );
  }
  final Ref ref;
  void _load() {
    final settings = FhRadioStudioProject.readSettings(
      ref.read(studioProvider).projectDir,
    );
    state = EditorOptions(
      syncPostLoop: settings['sync_post_loop'] == true,
      manualOnly: settings['manual_only'] == true,
      sirenEnabled: settings['siren_enabled'] == true,
      expansionEnabled: settings['expansion_enabled'] == true,
      slmEnabled: settings['seamless_loop_music'] == true,
    );
  }

  List<String> expansionOverflow() {
    final baseline = ref.read(baselinePlaylistCatalogProvider);
    final catalog = ref.read(playlistCatalogProvider);
    final plan = ref.read(effectivePlaylistPlanProvider);
    final issues = <String>[];
    final hasPlan = ref.read(playlistPlanProvider.notifier).hasUserPlan;
    for (final radio in catalog.radios.where(
      (r) => isUiSupportedRadio(name: r.name),
    )) {
      final allSources = <String>{};
      var maxCapacity = 0;
      for (final type in ['FreeRoam', 'Event']) {
        final original = baseline?.tracksOfRadio(radio.code, type).length ?? 0;
        final capacity = original > 0 ? original : radio.slot;
        if (capacity > maxCapacity) maxCapacity = capacity;
        final assigned = plan.assignmentsForRadio(radio.code, type);
        allSources.addAll(assigned.map((a) => a.source));
        final count = plan.hasBuiltinOverride(radio.code, type)
            ? 0
            : assigned.isNotEmpty || hasPlan
            ? assigned.length
            : catalog.modeOfList(radio.code, type) == StationMode.custom
            ? catalog.tracksOfRadio(radio.code, type).length
            : 0;
        if (count > capacity) {
          issues.add(
            '${radio.code} ${type == "Event" ? "比赛" : "漫游"}：$count / $capacity 首',
          );
        }
      }
      if (allSources.length > maxCapacity &&
          !issues.any((e) => e.startsWith('${radio.code} '))) {
        issues.add('${radio.code} 跨场景合计：${allSources.length} / $maxCapacity 首');
      }
    }
    return issues;
  }

  bool update({
    bool? syncPostLoop,
    bool? manualOnly,
    bool? sirenEnabled,
    bool? expansionEnabled,
    bool? slmEnabled,
  }) {
    if (expansionEnabled == false &&
        state.expansionEnabled &&
        expansionOverflow().isNotEmpty) {
      return false;
    }
    final next = EditorOptions(
      syncPostLoop: syncPostLoop ?? state.syncPostLoop,
      manualOnly: manualOnly ?? state.manualOnly,
      sirenEnabled: sirenEnabled ?? state.sirenEnabled,
      expansionEnabled: expansionEnabled ?? state.expansionEnabled,
      slmEnabled: slmEnabled ?? state.slmEnabled,
    );
    FhRadioStudioProject.writeSettings(
      ref.read(studioProvider).projectDir,
      syncPostLoop: next.syncPostLoop,
      manualOnly: next.manualOnly,
      sirenEnabled: next.sirenEnabled,
      expansionEnabled: next.expansionEnabled,
      slmEnabled: next.slmEnabled,
    );
    state = next;
    return true;
  }
}

final editorOptionsProvider =
    StateNotifierProvider<EditorOptionsController, EditorOptions>(
      (ref) => EditorOptionsController(ref),
    );
