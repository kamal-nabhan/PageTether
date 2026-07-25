// Fallback used whenever `dart:io` isn't available (Flutter web). See
// `desktop_drive_auth.dart` for the conditional export that picks between
// this file and `desktop_drive_auth_io.dart`.
import 'package:googleapis_auth/googleapis_auth.dart' as gapis_auth;

import 'auth_exceptions.dart';

Future<gapis_auth.AutoRefreshingAuthClient?> desktopRestoreSession() async =>
    null;

Future<gapis_auth.AutoRefreshingAuthClient> desktopSignIn({
  required void Function(Uri url) onConsentUrl,
}) async {
  throw const DriveAuthUnavailableException(
    'The desktop Drive sign-in flow is not available on this platform.',
  );
}

Future<void> desktopSignOut() async {}
