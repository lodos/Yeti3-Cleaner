# Apple publication — ViShu

Full iOS source now lives in `ios/`, with Xcode project, shared Archive scheme, tests, icons, privacy manifest and metadata. Team `49PHJ38L7T` is configured. Open `ios/Yeti3Cleaner.xcodeproj`, scheme Yeti3Cleaner. Register `ru.yeti3.cleaner.ios` in Developer Portal and create its App Store Connect record before Organizer upload. Current browser account can access ViShu in App Store Connect but Developer Portal rejects identifier registration (Access Unavailable). Membership alone does not resolve this denial.

`ios/Release/ExportOptions.plist` only exports, never uploads. Build1 has not been uploaded. For export packaging, `scripts/open-xcode-distribution.command` launches Xcode with system PATH.

`macos/Yeti3CleanerMac.xcodeproj` wraps the existing Rust/AppKit/SwiftUI application; no replacement application is introduced. Select Yeti3Cleaner-macOS and Archive. Requires Rust1.86.0 with both Apple targets. It packages the existing Universal app, preserving the normal data directory and native scan engine. Developer ID signing and notarization are required for trusted public distribution. This is not a sandboxed TestFlight target; an App Store runtime/access migration remains necessary. Do not submit it as if sandbox migration were complete.

No password, provisioning profile, generated archive or private signing material belongs in Git. Build outputs are ignored. See iOS Release documents for functional scope; their earlier device/test results are historical, not a fresh verification of this preparation.
