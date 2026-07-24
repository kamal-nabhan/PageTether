// Conditional export: picks the real `window_manager`-backed implementation
// everywhere `dart:io` is available (Windows/macOS/Linux/Android/iOS) and a
// no-op stub on web, where `dart:io` — and therefore `window_manager`,
// which imports it unconditionally — cannot be compiled in at all.
export 'desktop_fullscreen_stub.dart'
    if (dart.library.io) 'desktop_fullscreen_io.dart';
