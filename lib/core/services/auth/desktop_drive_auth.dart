// Conditional export: picks the real `googleapis_auth`-based loopback
// implementation everywhere `dart:io` is available (Windows/macOS/Linux/
// Android/iOS) and a no-op stub on web, where `dart:io` cannot be compiled
// in at all. Mirrors the pattern in
// `core/services/fullscreen/desktop_fullscreen.dart`.
//
// Only ever *called* on Windows/macOS/Linux — see the platform switch in
// `auth_notifier.dart` — even though it also compiles fine on mobile.
export 'desktop_drive_auth_stub.dart'
    if (dart.library.io) 'desktop_drive_auth_io.dart';
