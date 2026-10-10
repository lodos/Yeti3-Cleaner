# YETI³ Cleaner — Apple asset pack

## Contents

- `icons/iOS-AppIcon-1024.png`: opaque RGB icon included in `ios/Resources/Assets.xcassets/AppIcon.appiconset`. The universal 1024 px catalog is the Xcode source; Xcode compiles iPhone/iPad sizes into the app.
- `icons/macOS.iconset/`: ten PNG slots (16, 32, 128, 256, 512 px and @2x). Existing native Mac master and ICNS are also included in `icons/`.
- `screenshots/iphone-6.7/`: five native 1290×2796 screenshots.
- `screenshots/ipad-12.9/`: five native 2048×2732 screenshots.
- `manifest.json`: dimensions and SHA-256 for every publication image.

The full original application pack is `assets/generated/`: master artwork, About illustration, 16 tray states and 24 launcher animation frames. Keep these assets in the original native macOS application; iOS uses system symbols for its controls.

## Reproduction and verification

Run `swift scripts/prepare-apple-assets.swift` from the repository root. It derives the opaque iOS PNG and Mac iconset from the existing artwork, rejects flat/blank renders and updates the manifest. Inspect the generated icon visually before an archive. Icon checks must include decoded pixels, not only dimensions and hashes.

Five iPhone and five iPad screenshots have been accepted in App Store Connect (Cleaner, 6821407841). Build 2 was submitted to TestFlight and App Review on 2026-10-10. A subsequent asset audit found a black iOS icon; build 3 replaces it. See `../publication-status.json` for the verified current submission state.

Support: https://cleaner.yeti3.ru/static/cleaner/apple/app-support.html
Privacy: https://cleaner.yeti3.ru/static/cleaner/apple/privacy-policy.html

App Store Connect receives the app icon from the signed build. A separate ZIP of an asset pack is not uploaded as app metadata; screenshots are uploaded separately.
