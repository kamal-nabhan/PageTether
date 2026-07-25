// Conditional export: a real `window_manager`-backed implementation
// everywhere `dart:io` is available (desktop/mobile) and a no-op stub on
// web, where `dart:io` — and therefore `window_manager`, which imports it
// unconditionally — cannot be compiled in at all. See
// `desktop_fullscreen.dart` for the identical pattern already used elsewhere
// in this codebase.
export 'window_focus_service_stub.dart'
    if (dart.library.io) 'window_focus_service_io.dart';
