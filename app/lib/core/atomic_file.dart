import 'dart:convert';
import 'dart:io';

/// Publish a complete UTF-8 file using a private temporary directory on the same
/// filesystem. Readers see the old or new content; writers never share a temp.
void writeTextAtomicallySync(File file, String text) {
  file.parent.createSync(recursive: true);
  final temp = file.parent.createTempSync('.fh-radio-write-');
  try {
    final pending = File('${temp.path}/pending');
    pending.writeAsStringSync(text, encoding: utf8, flush: true);
    for (var attempt = 0; ; attempt++) {
      try {
        pending.renameSync(file.path);
        break;
      } on FileSystemException catch (error) {
        if (attempt >= 24 || !_transientRenameError(error, file)) rethrow;
        sleep(const Duration(milliseconds: 10));
      }
    }
  } finally {
    temp.deleteSync(recursive: true);
  }
}

Future<void> writeTextAtomically(File file, String text) async {
  await file.parent.create(recursive: true);
  final temp = await file.parent.createTemp('.fh-radio-write-');
  try {
    final pending = File('${temp.path}/pending');
    await pending.writeAsString(text, encoding: utf8, flush: true);
    for (var attempt = 0; ; attempt++) {
      try {
        await pending.rename(file.path);
        break;
      } on FileSystemException catch (error) {
        if (attempt >= 49 || !_transientRenameError(error, file)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  } finally {
    await temp.delete(recursive: true);
  }
}

// Antivirus/indexer handles and simultaneous renames can briefly deny replacement.
// Retry only Windows sharing/access errors; invalid destinations still fail fast.
bool _transientRenameError(FileSystemException error, File file) =>
    Platform.isWindows &&
    const {5, 32, 33}.contains(error.osError?.errorCode) &&
    !Directory(file.path).existsSync();
