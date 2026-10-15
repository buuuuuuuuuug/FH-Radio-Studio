/// Accept seconds, mm:ss, hh:mm:ss, decimal comma and written time units.
double parseTimeInput(String input) {
  var text = input
      .trim()
      .replaceAll('：', ':')
      .replaceAll('．', '.')
      .replaceAll('，', ',')
      .replaceAll(',', '.')
      .toLowerCase();
  if (text.isEmpty || text.startsWith('-')) {
    throw const FormatException('请输入非负时间');
  }
  final unit = RegExp(
    r'^(?:(\d+(?:\.\d+)?)\s*(?:小时|时|h)\s*)?(?:(\d+(?:\.\d+)?)\s*(?:分钟|分|m|min)\s*)?(?:(\d+(?:\.\d+)?)\s*(?:秒|s|sec)\s*)?(?:(\d+(?:\.\d+)?)\s*(?:毫秒|ms))?$',
  ).firstMatch(text);
  double result;
  if (unit != null && unit.groups([1, 2, 3, 4]).any((v) => v != null)) {
    result =
        (double.tryParse(unit[1] ?? '') ?? 0) * 3600 +
        (double.tryParse(unit[2] ?? '') ?? 0) * 60 +
        (double.tryParse(unit[3] ?? '') ?? 0) +
        (double.tryParse(unit[4] ?? '') ?? 0) / 1000;
  } else {
    text = text.replaceAll(RegExp(r'\s+'), '');
    final parts = text.split(':');
    if (parts.length > 3 ||
        parts.any((v) => !RegExp(r'^\d+(?:\.\d+)?$').hasMatch(v))) {
      throw const FormatException('支持秒数、分:秒.毫秒、时:分:秒或带单位的时间');
    }
    if (parts.length > 1 && parts.skip(1).any((v) => double.parse(v) >= 60)) {
      throw const FormatException('冒号后的分、秒应小于 60');
    }
    result = parts.fold<double>(
      0,
      (value, part) => value * 60 + double.parse(part),
    );
  }
  if (!result.isFinite || result < 0) throw const FormatException('时间无效');
  return result;
}

String editableTime(double seconds) {
  final ms = (seconds * 1000).round();
  return '${ms ~/ 60000}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}.${(ms % 1000).toString().padLeft(3, '0')}';
}
