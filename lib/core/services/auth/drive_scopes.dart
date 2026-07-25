/// OAuth scope requested everywhere Drive access is needed.
///
/// `drive.file` is the least-privilege Drive scope: it only grants access to
/// files the app itself created (or that the user explicitly opened with a
/// picker), never the user's whole Drive. Every platform's auth backend
/// requests exactly this one scope — see `core/services/auth/auth_notifier.dart`.
const String kDriveFileScope = 'https://www.googleapis.com/auth/drive.file';
