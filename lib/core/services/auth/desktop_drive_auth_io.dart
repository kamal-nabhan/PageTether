// Only ever compiled when `dart:io` is available (see the conditional
// export in `desktop_drive_auth.dart`) — never pulled into the web build.
//
// Desktop (Windows/macOS/Linux) OAuth loopback consent flow, used because
// `google_sign_in` has no federated implementation for Windows/Linux (macOS
// support exists but is kept on this same path for one consistent desktop
// story). This talks to Google's OAuth endpoints directly via
// `googleapis_auth`'s `clientViaUserConsent`, using the **Desktop app**
// OAuth client exported from Google Cloud Console into `credentials.json`
// at the project root (gitignored — never commit it).
import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart' as auth_io;
import 'package:googleapis_auth/googleapis_auth.dart' as gapis_auth;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'auth_exceptions.dart';
import 'drive_scopes.dart';

const _tokenFileName = 'drive_token.json';

/// Where the desktop OAuth token is cached: the OS-managed per-app support
/// directory (e.g. `%APPDATA%\pagetether\` on Windows), resolved via
/// `path_provider`. This is entirely outside the git working tree, so
/// unlike the old Flet prototype's `token.json` (which lived in the repo
/// root and had to be gitignored), this cache can never be accidentally
/// committed — there's no path for git to even see.
Future<File> _tokenCacheFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}${Platform.pathSeparator}$_tokenFileName');
}

/// Looks for `credentials.json` next to the project root (the working
/// directory `flutter run`/`flutter build` use) and, as a fallback, next to
/// the built executable (so a developer can also just copy it alongside a
/// packaged release build). Returns null if neither exists.
Future<File?> _findCredentialsFile() async {
  final candidates = <String>[
    '${Directory.current.path}${Platform.pathSeparator}credentials.json',
    '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}credentials.json',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (await file.exists()) return file;
  }
  return null;
}

Future<gapis_auth.ClientId> _loadClientId() async {
  final file = await _findCredentialsFile();
  if (file == null) {
    throw const DriveAuthUnavailableException(
      'credentials.json not found. Export an OAuth "Desktop app" client '
      'from Google Cloud Console and place it at the project root (or next '
      'to the built executable) as credentials.json.',
    );
  }
  try {
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    // Google Cloud Console wraps a Desktop-app client's fields under an
    // "installed" key (other client types use e.g. "web").
    final section = (raw['installed'] ?? raw['web']) as Map<String, dynamic>?;
    final clientId = section?['client_id'] as String?;
    final clientSecret = section?['client_secret'] as String?;
    if (clientId == null || clientSecret == null) {
      throw const FormatException('missing client_id/client_secret');
    }
    return gapis_auth.ClientId(clientId, clientSecret);
  } catch (e) {
    throw DriveAuthUnavailableException(
      'credentials.json is malformed ($e). Re-export a Desktop app OAuth '
      'client from Google Cloud Console.',
    );
  }
}

/// Silently restores a cached desktop session, if any, without opening a
/// browser. Returns null (never throws) if there's no cache, it can't be
/// read, or `credentials.json` is missing — callers fall back to
/// [desktopSignIn] for an explicit connect.
Future<gapis_auth.AutoRefreshingAuthClient?> desktopRestoreSession() async {
  try {
    final clientId = await _loadClientId();
    final cacheFile = await _tokenCacheFile();
    if (!await cacheFile.exists()) return null;

    final json =
        jsonDecode(await cacheFile.readAsString()) as Map<String, dynamic>;
    final credentials = gapis_auth.AccessCredentials.fromJson(json);
    final client = gapis_auth.autoRefreshingClient(
      clientId,
      credentials,
      http.Client(),
    );
    _persistOnRefresh(client);
    return client;
  } catch (_) {
    return null;
  }
}

/// Runs the interactive OAuth loopback consent flow: starts a local HTTP
/// server (`googleapis_auth` manages this internally — see
/// `clientViaUserConsent`), hands the caller the consent URL to open via
/// [onConsentUrl] (the UI layer opens it with `url_launcher`), and waits for
/// Google to redirect the browser back with the auth code. Persists the
/// resulting token so [desktopRestoreSession] can silently restore it next
/// launch, and keeps persisting it every time it's auto-refreshed.
Future<gapis_auth.AutoRefreshingAuthClient> desktopSignIn({
  required void Function(Uri url) onConsentUrl,
}) async {
  final clientId = await _loadClientId();
  final client = await auth_io.clientViaUserConsent(
    clientId,
    const [kDriveFileScope],
    (url) => onConsentUrl(Uri.parse(url)),
  );
  await _persist(client.credentials);
  _persistOnRefresh(client);
  return client;
}

/// Clears the local token cache. This is a local sign-out only — it does
/// not revoke the grant on Google's side (no `disconnect`/revoke call),
/// mirroring the scope of "sign out" everywhere else in the app.
Future<void> desktopSignOut() async {
  final cacheFile = await _tokenCacheFile();
  if (await cacheFile.exists()) {
    await cacheFile.delete();
  }
}

void _persistOnRefresh(gapis_auth.AutoRefreshingAuthClient client) {
  client.credentialUpdates.listen(_persist, onError: (_) {});
}

Future<void> _persist(gapis_auth.AccessCredentials credentials) async {
  final cacheFile = await _tokenCacheFile();
  await cacheFile.parent.create(recursive: true);
  await cacheFile.writeAsString(jsonEncode(credentials.toJson()));
}
