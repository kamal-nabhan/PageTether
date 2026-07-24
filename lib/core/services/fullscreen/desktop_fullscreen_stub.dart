// Fallback used whenever `dart:io` isn't available (Flutter web). See
// `desktop_fullscreen.dart` for the conditional export that picks between
// this file and `desktop_fullscreen_io.dart`.
Future<void> ensureDesktopWindowManagerInitialized() async {}

Future<void> setDesktopFullScreen(bool fullScreen) async {}

Future<bool> isDesktopFullScreen() async => false;
