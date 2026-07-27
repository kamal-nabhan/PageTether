# PageTether

PageTether is an open-source, cross-platform PDF reader built with Flutter.
Your books live in **your own Google Drive** (in a "PageTether Library"
folder), and your reading state — position, favorites, collections, metadata —
can optionally sync across devices through **your own Supabase project**
(bring-your-own-database, BYOD). PageTether itself never sees your files or
your sync data.

## Platform support

| Platform | Status |
|---|---|
| Web | Built & validated |
| Windows | Built & validated |
| Android | Built & validated |
| iOS | Buildable, not yet validated |
| macOS / Linux | Not currently included (no platform scaffolding in this repo yet) |

## Features

- **Reader**, built on [`pdfrx`](https://pub.dev/packages/pdfrx): continuous-scroll
  or horizontal page-flip layout, pinch/button zoom, a fullscreen/immersive
  reading mode, and resume-where-you-left-off.
- **Library**: a responsive dashboard with a sidebar on desktop and a bottom
  navigation bar on mobile; collections, favorites, a recent-books view,
  rename, editable/resettable book covers, and a choice of list or grid
  (three density levels) view.
- **Google Drive storage**: books are uploaded to a "PageTether Library"
  folder in your Drive, listed, cached locally on download, and deleted
  through the least-privilege `drive.file` OAuth scope (PageTether can only
  see files it created — not your whole Drive).
- **Cross-device sync (optional, BYOD Supabase)**: reading position, favorite
  status, collection membership, and metadata sync through a Supabase project
  you create and control, keyed by your Google sign-in identity. Per book,
  the reader pushes your position after a 4-second dwell on a page (and once
  more on close) and pulls on open plus every 30 seconds, adopting the remote
  page if it's newer.

## Prerequisites

- Flutter 3.44+ (Dart 3.12+)

## Setup

### 1. Google Cloud (required — Drive storage)

1. Create a project in the [Google Cloud Console](https://console.cloud.google.com/).
2. Enable the **Google Drive API**.
3. Configure the OAuth consent screen: type **External**, publishing status
   **Testing**, and add your own Google account as a **Test user**. Add
   scopes `drive.file`, `openid`, and `userinfo.email`.
4. Create OAuth client IDs:
   - **Desktop app** — download the JSON and save it as `credentials.json`
     in the repo root (used by the Windows/desktop build; gitignored, never
     commit it).
   - **Web application** — add `http://localhost:5000` as an authorized
     JavaScript origin. Its client ID is passed at run/build time via
     `--dart-define=GOOGLE_WEB_CLIENT_ID=<id>` — this same web client ID is
     also reused as `serverClientId` on Android/iOS, so one web client
     covers all three platforms.
   - **Android** — package name `io.github.kamalnabhan.pagetether`, plus
     your debug SHA-1 (`cd android && ./gradlew signingReport`).

### 2. Supabase (optional — cross-device sync)

1. Create a free project at [supabase.com](https://supabase.com).
2. Open the SQL Editor and run this repo's [`schema.sql`](schema.sql) once
   (it's idempotent, safe to re-run).
3. In the running app, open **Settings** and paste your project's **URL**
   and **anon key**. Synced data lives entirely in your own Supabase
   project — PageTether never sees it.

Note the security model documented at the top of `schema.sql`: rows are
keyed by a plain `user_id` column (your Google identity), not Supabase Auth,
so anyone holding your anon key can read/write your synced data. Keep the
anon key private; that's sufficient for a project used by one person or
household.

## Running the app

```bash
# Web
flutter run -d chrome --web-port=5000 --dart-define=GOOGLE_WEB_CLIENT_ID=<web-client-id>

# Windows (requires credentials.json in the repo root, see Setup)
flutter run -d windows

# Android
flutter run -d <device> --dart-define=GOOGLE_WEB_CLIENT_ID=<web-client-id>
```

## Building

```bash
flutter build web --release
flutter build windows --release
flutter build apk --release
```

### Android toolchain note

The Android build is pinned to **AGP 8.9.1 / Gradle 8.11.1 / Kotlin 2.1.0**
(see `android/settings.gradle.kts` and
`android/gradle/wrapper/gradle-wrapper.properties`) because the `file_picker`
plugin doesn't yet build against the newer AGP 9 default.

## Project structure

```
lib/
  core/               # Shared, feature-agnostic code
    models/           # Book, Collection, LibraryViewMode, SyncCredentials
    pdf/               # pdfrx source resolution + cover-thumbnail rendering
    services/
      auth/            # Google sign-in (web/desktop/mobile) + Drive OAuth scope
      drive/           # Google Drive upload/list/download-cache/delete
      fullscreen/      # Per-platform fullscreen/immersive mode
      sync/            # Supabase BYOD sync engine
      window/          # Desktop window-focus handling
    storage/           # Local persistence (SharedPreferences-backed)
    theme/             # App theme
  features/
    library/           # Library dashboard, collections, view-mode, widgets
    reader/             # PDF reader screen, page layouts, pagination bar
    settings/           # Sync credentials + sync status UI
  app.dart              # MaterialApp root
  main.dart             # Entry point / provider bootstrap
```

State management is via [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod).

## License

Apache License 2.0 — see [`LICENSE`](LICENSE).
