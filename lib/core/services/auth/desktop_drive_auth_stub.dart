// Fallback used whenever `dart:io` isn't available (Flutter web). See
// `desktop_drive_auth.dart` for the conditional export that picks between
// this file and `desktop_drive_auth_io.dart`.
import 'package:googleapis_auth/googleapis_auth.dart' as gapis_auth;

import 'auth_exceptions.dart';

/// Stub mirror of `desktop_drive_auth_io.dart`'s identity type — never
/// actually constructed here, but referenced by [DesktopAuthSession]'s type
/// signature so both conditional-export branches agree.
class DesktopIdentity {
  const DesktopIdentity({this.id, required this.email});
  final String? id;
  final String email;
}

class DesktopAuthSession {
  const DesktopAuthSession({required this.client, this.identity});
  final gapis_auth.AutoRefreshingAuthClient client;
  final DesktopIdentity? identity;
}

Future<DesktopAuthSession?> desktopRestoreSession() async => null;

Future<DesktopAuthSession> desktopSignIn({
  required void Function(Uri url) onConsentUrl,
}) async {
  throw const DriveAuthUnavailableException(
    'The desktop Drive sign-in flow is not available on this platform.',
  );
}

Future<void> desktopSignOut() async {}
