# AI Cleaner – Storage Cleaner (Android, Flutter)

Storage cleaner for Android: duplicate / similar / blurry photos, duplicate & screen-recorded videos, compression, duplicate contacts, past calendar events, app manager and a PIN-locked Secret Space. All analysis runs on-device.

- Package: `io.ld2t.ai_cleaner` · minSdk 29 · targetSdk 36
- Palette: `#0F2A1D` `#375534` `#6B9071` `#AEC3B0` `#E3EED4`
- [Privacy Policy](https://ldtrng.github.io/ai-cleaner-storage-cleaner/privacy-policy.html) · [Terms of Use](https://ldtrng.github.io/ai-cleaner-storage-cleaner/terms.html)
- Release checklist: [PLAY_STORE.md](PLAY_STORE.md)

## Build

```bash
flutter pub get
flutter build appbundle --release
```

Release signing reads `android/key.properties` + `android/upload-keystore.jks` (not committed). Without them the release build falls back to the debug key.

Debug/profile builds use Google's test AdMob units; only release builds use the real ad unit IDs.
