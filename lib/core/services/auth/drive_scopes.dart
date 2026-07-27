/// OAuth scope requested everywhere Drive access is needed.
///
/// `drive.file` is the least-privilege Drive scope: it only grants access to
/// files the app itself created (or that the user explicitly opened with a
/// picker), never the user's whole Drive. Every platform's auth backend
/// requests exactly this one scope — see `core/services/auth/auth_notifier.dart`.
const String kDriveFileScope = 'https://www.googleapis.com/auth/drive.file';

/// Identity scopes requested **only by the desktop loopback flow** (see
/// `desktop_drive_auth_io.dart`) so it can resolve a stable
/// `AuthNotifier.syncUserId`/`syncEmail` for Phase 4's Supabase sync — the
/// same way `google_sign_in`'s basic profile already gives web/mobile a
/// `GoogleSignInAccount.id`/`.email` for free. Together these two scopes let
/// the desktop flow call Google's OIDC userinfo endpoint
/// (`https://www.googleapis.com/oauth2/v3/userinfo`) and get back a stable
/// `sub` (subject id) plus `email` — see `_fetchIdentity` in
/// `desktop_drive_auth_io.dart`.
const String kOpenIdScope = 'openid';
const String kUserInfoEmailScope =
    'https://www.googleapis.com/auth/userinfo.email';
