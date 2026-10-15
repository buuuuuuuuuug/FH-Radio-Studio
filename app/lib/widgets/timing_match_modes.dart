const timingMatchModes = <String, String>{
  'auto': '自动匹配（唯一结果）',
  'filename': '文件名',
  'title': '歌曲名',
  'title-artist': '歌曲名_歌手',
  'artist-title': '歌手_歌曲名',
};
const timingCsvTemplate =
    'Filename,TD,PD,TL-A,TL-B,PL-A,PL-B\n示例歌曲.wav,0:19.185,2:02.350,1:06.660,3:25.883,1:06.660,3:25.883';
String timingCsvTemplateFor({bool includeRadio = false}) => includeRadio
    ? 'Filename,Radio_station,TD,PD,TL-A,TL-B,PL-A,PL-B\n示例歌曲.wav,R1,0:19.185,,1:06.660,,,'
    : timingCsvTemplate;
