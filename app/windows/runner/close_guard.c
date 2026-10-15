/* The Dart listener is asynchronous: no Dart executes on the platform thread. */
#include <windows.h>
#include <wchar.h>
static HWND studio_window;
static WNDPROC previous_proc;
static void (*request_close)(void);
static int close_allowed;
static LRESULT CALLBACK guard_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_CLOSE && !close_allowed && request_close) { request_close(); return 0; }
  return CallWindowProcW(previous_proc, window, message, wparam, lparam);
}
static BOOL CALLBACK find_window(HWND window, LPARAM data) {
  DWORD process; WCHAR class_name[100];
  GetWindowThreadProcessId(window, &process);
  if (process != GetCurrentProcessId()) return TRUE;
  if (!GetClassNameW(window, class_name, 100)) return TRUE;
  if (wcscmp(class_name, L"FLUTTER_RUNNER_WIN32_WINDOW") != 0) return TRUE;
  studio_window = window; return FALSE;
}
__declspec(dllexport) int fh_install_close_guard(void (*notify)(void)) {
  if (previous_proc) return 1;
  EnumWindows(find_window, 0);
  if (!studio_window || !notify) return 0;
  request_close = notify; close_allowed = 0;
  previous_proc = (WNDPROC)SetWindowLongPtrW(studio_window, GWLP_WNDPROC, (LONG_PTR)guard_proc);
  return previous_proc != 0;
}
__declspec(dllexport) void fh_allow_window_close(void) {
  close_allowed = 1; PostMessageW(studio_window, WM_CLOSE, 0, 0);
}
__declspec(dllexport) void fh_remove_close_guard(void) {
  if (studio_window && previous_proc && IsWindow(studio_window)) {
    SetWindowLongPtrW(studio_window, GWLP_WNDPROC, (LONG_PTR)previous_proc);
  }
  request_close = 0; previous_proc = 0; studio_window = 0;
}
