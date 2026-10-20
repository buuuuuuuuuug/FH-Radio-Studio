import 'dart:io';

String playlistActionFailure(String action, Object error) {
  if (error is FileSystemException) {
    if (const {28, 39, 112}.contains(error.osError?.errorCode)) {
      return '$action失败：磁盘空间不足，请清理工作区所在磁盘后重试。';
    }
    return '$action失败：${error.message}${error.path == null ? '' : '（${error.path}）'}';
  }
  return '$action失败：${error is FormatException ? error.message : error}';
}
