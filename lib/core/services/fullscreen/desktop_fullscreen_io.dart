// Only ever compiled when `dart:io` is available (see the conditional
// export in `desktop_fullscreen.dart`) — never pulled into the web build,
// which is important because `window_manager` itself imports `dart:io`
// unconditionally.
import 'dart:io';

import 'package:window_manager/window_manager.dart';

/// `window_manager` only ships Windows/macOS/Linux platform
/// implementations; calling it on Android/iOS (where `dart:io` is also
/// available) would throw a `MissingPluginException`, so every entry point
/// below guards on the supported desktop platforms itself.
bool get _isSupportedDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

Future<void> ensureDesktopWindowManagerInitialized() async {
  if (!_isSupportedDesktop) return;
  await windowManager.ensureInitialized();
}

Future<void> setDesktopFullScreen(bool fullScreen) async {
  if (!_isSupportedDesktop) return;
  await windowManager.setFullScreen(fullScreen);
}

Future<bool> isDesktopFullScreen() async {
  if (!_isSupportedDesktop) return false;
  return windowManager.isFullScreen();
}
