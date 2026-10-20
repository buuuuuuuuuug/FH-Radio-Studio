import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/playlist_capacity.dart';
import '../domain/radio_library.dart';
import 'playlist_catalog_state.dart';

final playlistCapacityPolicyProvider = Provider<PlaylistCapacityPolicy>((ref) {
  final baseline = ref.watch(baselinePlaylistCatalogProvider);
  final catalog = ref.watch(playlistCatalogProvider);
  final radios = {
    for (final r in kRadios) r.code: r,
    for (final r in catalog.radios) r.code: r,
    for (final r in baseline?.radios ?? <RadioStation>[]) r.code: r,
  };
  return PlaylistCapacityPolicy({
    for (final r in radios.values.where(
      (r) => isUiSupportedRadio(name: r.name),
    ))
      r.code: {
        for (final type in ['FreeRoam', 'Event'])
          type: (baseline?.tracksOfRadio(r.code, type).length ?? 0) > 0
              ? baseline!.tracksOfRadio(r.code, type).length
              : r.slot,
      },
  });
});
