# App icon

Two source images live here and feed `flutter_launcher_icons` (configured in
`pubspec.yaml` under the `flutter_launcher_icons:` block):

- **`pagetether_icon.png`** — square, fully opaque, ~1024×1024. Used as-is
  for iOS, web, and Windows, and as the base for Android's non-adaptive
  fallback icon.
- **`pagetether_icon_foreground.png`** — transparent background, the logo
  scaled down and centered so it sits inside Android adaptive icons' "safe
  zone" (the ~66% center circle every launcher shape is guaranteed not to
  clip). Used only as the Android adaptive foreground layer, paired with the
  solid `adaptive_icon_background` color already set in `pubspec.yaml`.

## Replacing the icon

1. Drop your new artwork in as these same two files (same names, same
   folder), matching the specs above — square/opaque for the main icon,
   transparent/safe-zone-padded for the foreground. If you're starting from
   raw designer exports instead, see `tool/generate_icons.dart` below.
2. Regenerate the platform icon files:
   ```
   dart run flutter_launcher_icons
   ```
3. Rebuild (and reinstall on-device, if testing on Android/iOS — icon
   changes usually aren't picked up by a hot reload/restart, only a fresh
   install) so the new icon actually shows up.

## Deriving these from raw designer PNGs

`tool/generate_icons.dart` is a one-off script that produces both files above
from two raw exports dropped in the repo root (`PageTether_Icon.png` for the
main icon, `PageTether_Icon-removebg-preview.png` — background already
removed — for the foreground). It squares/pads and downscales the main icon
to 1024×1024 on an opaque background, and trims/centers/scales the
foreground logo into the adaptive safe zone on a transparent 1024×1024
canvas. Run it with:

```
dart run tool/generate_icons.dart
```

then follow steps 2–3 above. It's not part of the app or test suite, so
`flutter test`/`flutter build` never touch it.
