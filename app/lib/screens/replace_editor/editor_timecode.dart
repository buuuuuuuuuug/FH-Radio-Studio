String formatEditorTimecode(double? seconds) {
  if (seconds == null || !seconds.isFinite) return '—';
  final ms = (seconds * 1000).round().clamp(0, 9007199254740991);
  final minutes = ms ~/ 60000;
  final secs = (ms ~/ 1000) % 60;
  return '$minutes:${secs.toString().padLeft(2, '0')}.${(ms % 1000).toString().padLeft(3, '0')}';
}
