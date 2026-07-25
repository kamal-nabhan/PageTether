// Only ever compiled when `dart:io` is available (see the conditional
// export in `window_focus_service.dart`) — never pulled into the web build,
// which is important because `window_manager` itself imports `dart:io`
// unconditionally.
import 'dart:io';

import 'package:window_manager/window_manager.dart';

/// `window_manager` only ships Windows/macOS/Linux platform
/// implementations; calling it on Android/iOS (where `dart:io` is also
/// available) would throw a `MissingPluginException`, so every entry point
/// below guards on the supported desktop platforms itself — mirrors
/// `desktop_fullscreen_io.dart`'s `_isSupportedDesktop`.
bool get _isSupportedDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

class _DesktopWindowFocusListener with WindowListener {
  _DesktopWindowFocusListener(this._onFocus);

  final void Function() _onFocus;

  @override
  void onWindowFocus() => _onFocus();
}

/// Tracks the single currently-registered listener so
/// [registerDesktopWindowFocusListener] can swap it out cleanly (rather than
/// stacking listeners) if called more than once — e.g. `LibraryScreen`
/// hot-reloading or remounting.
_DesktopWindowFocusListener? _activeListener;

/// Registers [onFocus] to fire every time the desktop window regains OS
/// focus (e.g. alt-tabbing back in, or clicking the taskbar icon) — the
/// scenario `AppLifecycleState.resumed` often misses on desktop, since many
/// window managers never emit it just for a focus change. A no-op on
/// Android/iOS (`window_manager` has no implementation there) and, via the
/// conditional export, on web.
void registerDesktopWindowFocusListener(void Function() onFocus) {
  if (!_isSupportedDesktop) return;
  unregisterDesktopWindowFocusListener();
  final listener = _DesktopWindowFocusListener(onFocus);
  _activeListener = listener;
  windowManager.addListener(listener);
}

/// Unregisters whatever listener [registerDesktopWindowFocusListener] most
/// recently registered, if any. Safe to call even if nothing is registered.
void unregisterDesktopWindowFocusListener() {
  final listener = _activeListener;
  if (listener == null) return;
  windowManager.removeListener(listener);
  _activeListener = null;
}
