import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

typedef _Install = Int32 Function(Pointer<NativeFunction<Void Function()>>);

/// Keeps the native Windows runner open until pending edits are resolved.
class WindowsCloseGuard {
  WindowsCloseGuard._(this._callback, this._allowClose, this._remove);
  final NativeCallable<Void Function()> _callback;
  final void Function() _allowClose;
  final void Function() _remove;
  static WindowsCloseGuard? install(Future<void> Function() onClose) {
    if (!Platform.isWindows) return null;
    final libraryPath = p.join(
      p.dirname(Platform.resolvedExecutable),
      'fh_radio_close_guard.dll',
    );
    if (!File(libraryPath).existsSync()) return null;
    NativeCallable<Void Function()>? callback;
    try {
      final lib = DynamicLibrary.open(libraryPath);
      callback = NativeCallable<Void Function()>.listener(() {
        unawaited(onClose());
      });
      final install = lib
          .lookupFunction<
            _Install,
            int Function(Pointer<NativeFunction<Void Function()>>)
          >('fh_install_close_guard');
      if (install(callback.nativeFunction) == 0) {
        debugPrint('Windows close guard could not find the runner window');
        callback.close();
        return null;
      }
      if (Platform.environment['FH_RADIO_STUDIO_UI_TEST_PROJECT'] != null) {
        debugPrint('Windows close guard installed');
      }
      return WindowsCloseGuard._(
        callback,
        lib.lookupFunction<Void Function(), void Function()>(
          'fh_allow_window_close',
        ),
        lib.lookupFunction<Void Function(), void Function()>(
          'fh_remove_close_guard',
        ),
      );
    } on Object catch (error) {
      callback?.close();
      debugPrint('Windows close guard unavailable: $error');
      return null;
    }
  }

  void closeApproved() => _allowClose();
  void dispose() {
    _remove();
    _callback.close();
  }
}
