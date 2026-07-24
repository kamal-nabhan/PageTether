import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'desktop_fullscreen.dart' as desktop;
import 'web_fullscreen.dart' as web_fullscreen;

/// Cross-platform "true" fullscreen control, layered underneath the
/// reader's baseline in-app immersive mode (which always works, on every
/// platform, by simply hiding the app's own chrome widgets).
///
/// - Web: the browser's Fullscreen API on the document element.
/// - Windows/macOS/Linux: native OS fullscreen via `window_manager`.
/// - Android/iOS: immersive system UI mode (hides status/nav bars).
/// - Anything unsupported: no-op — the in-app immersive mode still covers
///   it, so nothing ever crashes or gets stuck.
abstract final class FullscreenService {
  /// Call once at app startup (before/around `runApp`). Safe to call on
  /// every platform — it only does real work on Windows/macOS/Linux.
  static Future<void> initializeForDesktop() =>
      desktop.ensureDesktopWindowManagerInitialized();

  static Future<void> enter() async {
    if (kIsWeb) {
      await web_fullscreen.requestWebFullscreen();
      return;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        await desktop.setDesktopFullScreen(true);
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      case TargetPlatform.fuchsia:
        break;
    }
  }

  static Future<void> exit() async {
    if (kIsWeb) {
      await web_fullscreen.exitWebFullscreen();
      return;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        await desktop.setDesktopFullScreen(false);
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      case TargetPlatform.fuchsia:
        break;
    }
  }
}
