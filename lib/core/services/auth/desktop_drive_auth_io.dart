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
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart' as auth_io;
import 'package:googleapis_auth/googleapis_auth.dart' as gapis_auth;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'auth_exceptions.dart';
import 'drive_scopes.dart';

const _tokenFileName = 'drive_token.json';
const _identityFileName = 'drive_identity.json';

/// Desktop OAuth "Desktop app" client, embedded into release builds at build
/// time via `--dart-define` so published users never supply their own
/// credentials.json. Empty in dev builds that omit the defines — [_loadClientId]
/// then falls back to reading a local credentials.json. An installed/desktop
/// app's client secret is not confidential per OAuth 2.0 for Native Apps
/// (RFC 8252), so baking it into the distributed binary is expected practice.
const _embeddedDesktopClientId = String.fromEnvironment(
  'GOOGLE_DESKTOP_CLIENT_ID',
);
const _embeddedDesktopClientSecret = String.fromEnvironment(
  'GOOGLE_DESKTOP_CLIENT_SECRET',
);

/// Minimal sync identity resolved from Google's OIDC userinfo endpoint (see
/// [_fetchIdentity]) once the desktop loopback flow also holds the
/// `openid`/`userinfo.email` scopes (see `drive_scopes.dart`). [id] is the
/// stable Google `sub` (subject) id — preferred as `AuthNotifier.syncUserId`
/// — with [email] as the fallback identity key and the value shown to the
/// user.
class DesktopIdentity {
  const DesktopIdentity({this.id, required this.email});

  final String? id;
  final String email;

  Map<String, dynamic> toJson() => {'id': id, 'email': email};

  factory DesktopIdentity.fromJson(Map<String, dynamic> json) =>
      DesktopIdentity(id: json['id'] as String?, email: json['email'] as String);
}

/// Result of a successful desktop connect/restore: the Drive-authorized
/// client plus whatever sync identity could be resolved alongside it.
/// [identity] is null when the userinfo call failed or hasn't been attempted
/// yet — notably true for a session cached *before* this feature shipped,
/// whose access token only ever held `drive.file` — callers should treat a
/// null [identity] as "Drive is connected but sync is not available", not as
/// an error.
class DesktopAuthSession {
  const DesktopAuthSession({required this.client, this.identity});

  final gapis_auth.AutoRefreshingAuthClient client;
  final DesktopIdentity? identity;
}

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

/// Sibling cache file to [_tokenCacheFile] holding the last-resolved
/// [DesktopIdentity], so a silent [desktopRestoreSession] doesn't need a
/// network round trip just to know the signed-in email/id.
Future<File> _identityCacheFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}${Platform.pathSeparator}$_identityFileName');
}

Future<DesktopIdentity?> _loadCachedIdentity() async {
  try {
    final file = await _identityCacheFile();
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return DesktopIdentity.fromJson(json);
  } catch (_) {
    return null;
  }
}

Future<void> _persistIdentity(DesktopIdentity identity) async {
  final file = await _identityCacheFile();
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(identity.toJson()));
}

/// Calls Google's OIDC userinfo endpoint through [client] (which attaches
/// the bearer access token to every request it makes) to resolve the
/// signed-in user's stable `sub` id and email. Returns null — never
/// throws — if the call fails, most commonly because the authorized access
/// token doesn't actually hold the `openid`/`userinfo.email` scopes (e.g. a
/// token cached before this feature shipped).
Future<DesktopIdentity?> _fetchIdentity(http.Client client) async {
  try {
    final response = await client.get(
      Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
    );
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final email = json['email'] as String?;
    if (email == null) return null;
    return DesktopIdentity(id: json['sub'] as String?, email: email);
  } catch (_) {
    return null;
  }
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
  // Prefer the client baked into the build — this is how distributed releases
  // ship, so end users never need to supply a credentials.json.
  if (_embeddedDesktopClientId.isNotEmpty &&
      _embeddedDesktopClientSecret.isNotEmpty) {
    return gapis_auth.ClientId(
      _embeddedDesktopClientId,
      _embeddedDesktopClientSecret,
    );
  }
  // Fall back to a local credentials.json (developer machines / dev builds).
  final file = await _findCredentialsFile();
  if (file == null) {
    throw const DriveAuthUnavailableException(
      'No Google Drive desktop client configured. Either build with '
      '--dart-define=GOOGLE_DESKTOP_CLIENT_ID=… '
      '--dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=…, or export an OAuth '
      '"Desktop app" client from Google Cloud Console and place it at the '
      'project root (or next to the executable) as credentials.json.',
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
///
/// [DesktopAuthSession.identity] is loaded from the identity cache file if
/// present; failing that, it's re-resolved with one userinfo call (see
/// [_fetchIdentity]) and persisted for next time — this only ever fails
/// silently (leaving `identity: null`) for a token cached before this
/// feature shipped, whose scopes don't include `openid`/`userinfo.email`.
Future<DesktopAuthSession?> desktopRestoreSession() async {
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

    var identity = await _loadCachedIdentity();
    if (identity == null) {
      identity = await _fetchIdentity(client);
      if (identity != null) unawaited(_persistIdentity(identity));
    }
    return DesktopAuthSession(client: client, identity: identity);
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
/// launch, and keeps persisting it every time it's auto-refreshed. Also
/// resolves and persists [DesktopAuthSession.identity] via one userinfo
/// call, now that the freshly-granted scopes include `openid`/
/// `userinfo.email` (see `drive_scopes.dart`).
Future<DesktopAuthSession> desktopSignIn({
  required void Function(Uri url) onConsentUrl,
}) async {
  final clientId = await _loadClientId();
  final client = await auth_io.clientViaUserConsent(
    clientId,
    const [kDriveFileScope, kOpenIdScope, kUserInfoEmailScope],
    (url) => onConsentUrl(Uri.parse(url)),
  );
  await _persist(client.credentials);
  _persistOnRefresh(client);

  final identity = await _fetchIdentity(client);
  if (identity != null) await _persistIdentity(identity);
  return DesktopAuthSession(client: client, identity: identity);
}

/// Clears the local token + identity cache. This is a local sign-out only —
/// it does not revoke the grant on Google's side (no `disconnect`/revoke
/// call), mirroring the scope of "sign out" everywhere else in the app.
Future<void> desktopSignOut() async {
  final cacheFile = await _tokenCacheFile();
  if (await cacheFile.exists()) {
    await cacheFile.delete();
  }
  final identityFile = await _identityCacheFile();
  if (await identityFile.exists()) {
    await identityFile.delete();
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
