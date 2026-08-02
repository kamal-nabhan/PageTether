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

/// Whether [setDesktopFullScreen] unmaximized the window on the way into
/// fullscreen (see that function's Windows-only workaround below) and so
/// owes it a re-maximize on the way back out.
bool _wasMaximizedBeforeFullScreen = false;

Future<void> setDesktopFullScreen(bool fullScreen) async {
  if (!_isSupportedDesktop) return;
  if (fullScreen && Platform.isWindows) {
    // Workaround for a window_manager 0.5.2 quirk on Windows: its
    // `WindowManager::SetFullScreen` (windows/window_manager.cpp) only
    // strips the window frame — via its own internal `SetAsFrameless()` —
    // when the window is *not already maximized* at the moment fullscreen
    // is requested (it captures `g_maximized_before_fullscreen` up front and
    // skips `SetAsFrameless()` entirely when that's true). Skip that call
    // and the plugin's WM_NCCALCSIZE handler never gets a frameless window
    // to hit its "return 0, no non-client area" branch, so the window still
    // paints its normal title bar/border at the fullscreen-sized bounds —
    // exactly the "edge instead of true borderless" symptom. A reader
    // window that's maximized before the user hits fullscreen is an entirely
    // normal flow, so this isn't an edge case. Unmaximizing first forces
    // that internal flag false so the frameless path actually runs; restored
    // by re-maximizing on the way back out below, so exiting fullscreen
    // doesn't leave a maximized window merely "restored".
    _wasMaximizedBeforeFullScreen = await windowManager.isMaximized();
    if (_wasMaximizedBeforeFullScreen) await windowManager.unmaximize();
  }
  await windowManager.setFullScreen(fullScreen);
  if (!fullScreen && _wasMaximizedBeforeFullScreen) {
    _wasMaximizedBeforeFullScreen = false;
    await windowManager.maximize();
  }
}

Future<bool> isDesktopFullScreen() async {
  if (!_isSupportedDesktop) return false;
  return windowManager.isFullScreen();
}
