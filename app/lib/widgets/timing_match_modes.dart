const timingMatchModes = <String, String>{
  'auto': '自动匹配（唯一结果）',
  'filename': '文件名',
  'title': '歌曲名',
  'title-artist': '歌曲名_歌手',
  'artist-title': '歌手_歌曲名',
};
const timingCsvTemplate =
    'Filename,TD,PD,TL-A,TL-B,PL-A,PL-B\n示例歌曲.wav,0:19.185,2:02.350,1:06.660,3:25.883,1:06.660,3:25.883';
const timingTimeUnits = <String, String>{
  'time': '时间（分:秒.毫秒 / 秒数）',
  'samples': '采样点（固定 48000 Hz）',
};

String timingCsvTemplateFor({
  bool includeRadio = false,
  String timeUnit = 'time',
  String matchMode = 'auto',
}) {
  final identity = switch (matchMode) {
    'title' => '示例歌曲',
    'title-artist' => '示例歌曲_示例歌手',
    'artist-title' => '示例歌手_示例歌曲',
    _ => '示例歌曲.wav',
  };
  final positions = timeUnit == 'samples'
      ? '920880,5872800,3199680,9882384,3199680,9882384'
      : '0:19.185,2:02.350,1:06.660,3:25.883,1:06.660,3:25.883';
  return 'Filename,${includeRadio ? 'Radio_station,' : ''}TD,PD,TL-A,TL-B,PL-A,PL-B\n'
      '$identity,${includeRadio ? 'R1,' : ''}$positions';
}
