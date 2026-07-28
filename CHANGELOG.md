# Changelog

All notable changes to PageTether are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-07-28

### Added

- **Release automation**: a GitHub Actions release workflow publishes the web
  bundle, Android APKs (per-ABI + universal), and the Windows build to the
  GitHub Releases page on each version tag.
- **Signed Android releases**: release builds are signed with a release
  keystore (`key.properties` locally / GitHub secrets in CI), so Google Drive
  sign-in works on the published APK.

### Changed

- Google OAuth consent screen published to production, so any Google account
  can sign in (previously limited to test users).

## [0.1.0] - 2026-07-27

Initial cross-platform release of the Flutter rewrite (web, Windows, Android).

### Added

- **Reader**: `pdfrx`-based PDF viewing with continuous scroll and page-flip
  modes, pinch/scroll zoom, fullscreen, and resume-from-last-page.
- **Library**: responsive grid/list library with collections, favorites,
  recently-read, book renaming, cover art, and adjustable view density.
- **Google Drive storage**: sign-in and per-book upload/list/download/delete
  using the narrow `drive.file` scope, with idempotent delete and local-cache
  reuse so re-opening a book doesn't always re-download it.
- **BYOD Supabase sync**: user-supplied Supabase project (URL + anon key)
  syncs reading position, favorites, and collections across devices.
- **CI**: GitHub Actions workflow running `flutter analyze` and the test
  suite (51 tests) on every push/PR.

[0.1.1]: https://github.com/kamal-nabhan/PageTether/releases/tag/v0.1.1
[0.1.0]: https://github.com/kamal-nabhan/PageTether/releases/tag/v0.1.0
