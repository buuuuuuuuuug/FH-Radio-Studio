import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_state.dart';

class LibraryColumnSpec {
  const LibraryColumnSpec(this.id, this.minimum, this.initial);
  final String id;
  final double minimum, initial;
}

Map<String, double> fitLibraryColumns(
  double available,
  List<LibraryColumnSpec> specs,
  Map<String, double> saved,
) {
  final minimum = specs.fold<double>(0, (v, s) => v + s.minimum);
  final desired = {
    for (final s in specs) s.id: math.max(s.minimum, saved[s.id] ?? s.initial),
  };
  final extra = specs.fold<double>(0, (v, s) => v + desired[s.id]! - s.minimum);
  final room = math.max(0.0, available - minimum);
  return {
    for (final s in specs)
      s.id:
          s.minimum +
          (extra > 0
              ? (desired[s.id]! - s.minimum) * room / extra
              : room / specs.length),
  };
}

class LibraryColumnsController extends StateNotifier<Map<String, double>> {
  LibraryColumnsController(this.prefs) : super(const {}) {
    try {
      final raw = jsonDecode(prefs.getString('library.columns.v1') ?? '{}');
      if (raw is Map) {
        state = {
          for (final e in raw.entries)
            if (e.value is num && (e.value as num).isFinite && e.value > 0)
              '${e.key}': (e.value as num).toDouble(),
        };
      }
    } on Object {
      /* Use responsive defaults for invalid preferences. */
    }
  }
  final SharedPreferences prefs;
  Timer? _timer;
  ({
    List<LibraryColumnSpec> specs,
    Map<String, double> widths,
    int index,
    double origin,
  })?
  _drag;
  void beginResize(
    List<LibraryColumnSpec> specs,
    Map<String, double> widths,
    int index,
    double x,
  ) {
    _drag = (specs: specs, widths: Map.of(widths), index: index, origin: x);
  }

  void updateResize(double x) {
    final drag = _drag;
    if (drag == null || !x.isFinite) return;
    resize(drag.specs, drag.widths, drag.index, x - drag.origin);
  }

  void endResize() {
    _drag = null;
    flush();
  }

  void resize(
    List<LibraryColumnSpec> specs,
    Map<String, double> widths,
    int index,
    double delta,
  ) {
    if (!delta.isFinite || specs.length < 2) return;
    final other = index + 1 < specs.length ? index + 1 : index - 1;
    final a = specs[index], b = specs[other];
    final change = delta.clamp(
      a.minimum - widths[a.id]!,
      widths[b.id]! - b.minimum,
    );
    state = {
      ...state,
      ...widths,
      a.id: widths[a.id]! + change,
      b.id: widths[b.id]! - change,
    };
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), flush);
  }

  void flush() {
    _timer?.cancel();
    prefs.setString('library.columns.v1', jsonEncode(state));
  }

  void reset() {
    _timer?.cancel();
    _drag = null;
    state = const {};
    prefs.remove('library.columns.v1');
  }

  @override
  void dispose() {
    if (_timer?.isActive ?? false) flush();
    _timer?.cancel();
    super.dispose();
  }
}

final libraryColumnsProvider =
    StateNotifierProvider<LibraryColumnsController, Map<String, double>>(
      (ref) => LibraryColumnsController(ref.watch(sharedPreferencesProvider)),
    );
