/// Keep a zoomed view still until playback reaches its outer ten percent.
/// Page forward/backward with overlap so the next selection area stays stable.
({double start, double end}) pagedPlaybackWindow({
  required double duration,
  required double start,
  required double end,
  required double playhead,
}) {
  if (!duration.isFinite || duration <= 0) return (start: 0, end: 0);
  final span = (end - start).clamp(0.0, duration);
  if (!span.isFinite || span <= 0 || span >= duration) {
    return (start: 0, end: duration);
  }
  final left = start.clamp(0.0, duration - span);
  final position = playhead.isFinite ? playhead.clamp(0.0, duration) : left;
  const edge = .1;
  final epsilon = span * 1e-9;
  var next = left;
  if (position > left + span * (1 - edge) + epsilon) {
    next = position - span * edge;
  } else if (position < left + span * edge - epsilon) {
    next = position - span * (1 - edge);
  }
  next = next.clamp(0.0, duration - span);
  return (start: next, end: next + span);
}
