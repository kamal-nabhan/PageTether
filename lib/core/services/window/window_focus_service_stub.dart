// Fallback used whenever `dart:io` isn't available (Flutter web). See
// `window_focus_service.dart` for the conditional export that picks between
// this file and `window_focus_service_io.dart`.
void registerDesktopWindowFocusListener(void Function() onFocus) {}

void unregisterDesktopWindowFocusListener() {}
