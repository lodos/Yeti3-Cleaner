# Apple compatibility audit — 2026-10-11

Scope: published Apple documentation and release notes, SDK availability, current code and real-device results. This is not a promise about unannounced API or every future OS build.

## Current and announced releases

| Area | Evidence and action | Remaining verification |
| --- | --- | --- |
| iOS/iPadOS 27 | Built against installed Xcode 27 SDK. Launch screen is declared. PhotoKit nullable dates are handled; private file-size KVC and originalFilename are not used. | iOS 27 device/runtime acceptance; physical devices here run 26.6 and 26.4.2. |
| iOS/iPadOS 27.1 / iPhone Duo | Apple announced the new form factor. Dashboard uses ViewThatFits and scaled title; lists and settings scroll without fixed screen dimensions. Rotation and accessibility text capture included in UI tests. | Xcode 27.1 simulator/device poses and store screenshots. Installed SDK is 27.0, not 27.1. |
| iOS/macOS 27.2 beta | Reviewed published beta notes. No cross-app tracking or ATT prompt is introduced. StoreKit storefront events invalidate and reload requested prices, with generation protection against stale responses. | Xcode 27.2 beta, real Sandbox purchases/refunds and storefront changes. |
| Continued Processing, iOS 26+ | Explicit per-profile opt-in, user starts analysis, system progress/cancel, immediate-or-fail strategy, cancellation and bounded CPU work. Auto-started analysis never requests this mode. Concrete job IDs avoid wildcard handler dispatch ambiguity on early 26 builds. | Long real background execution and expiration/system cancellation on controlled media. Registration and repeat submission accepted by both devices; file analysis survives the application's background transition handler. |
| BGProcessing, iOS 27 | Async submitTaskRequest used behind availability check; older OS uses existing submit API. Overview remains metadata-only, no network requirement, 250 assets/10 seconds cooperative budget. | Real OS-selected wakeup; runtime may defer indefinitely. |
| PhotoKit | Spatial images excluded from JPEG conversion; Live, HDR, RAW, panorama and edited resources remain excluded. Original preserved. Burst representatives protected by default. Limited contacts handled on iOS 18+. | Test fixtures for spatial/RAW/HDR/Live and permission-revocation while deleting. |
| macOS 27 | Full native UI launched and inspected on actual macOS 27.0 (26A428), Apple Silicon. NSOpenPanel keeps directory-only selection; no allowedContentTypes setter can reset its flags. Native background overview is bounded, opt-in and power/thermal gated. | Intel hardware and older supported macOS runtime. |
| Intel / macOS 28 | Native and Catalyst binaries contain arm64 and x86_64. Apple notes Intel-only non-game applications become incompatible on 28; native arm64 avoids dependence on that compatibility layer. | No macOS 28 runtime claim; Intel binary does not imply old OS support. Minimum macOS 14. |
| Neural Engine / GPU background | No background inference, large models or GPU entitlement. No decorative animation/display timer. | Representative large-library CPU, RAM, energy and thermal measurements. |
| StoreKit 27 Bundles/Suites | Shared network entitlement and StoreKit 2 foundation retained. No unconfigured auto-renewable bundle product is offered or client-granted. | Separate product configuration and Apple eligibility/agreements if owner elects to introduce bundles. |

## Sources

- [iOS/iPadOS 27 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes)
- [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
- [iOS/iPadOS 27.2 beta notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27_2-release-notes)
- [macOS 27.2 beta notes](https://developer.apple.com/documentation/macos-release-notes/macos-27_2-release-notes)
- [Announced beta releases and iPhone Duo](https://developer.apple.com/news/?id=rfb1rooi)
- [Long-running tasks on iOS/iPadOS](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)
- [Storefront updates](https://developer.apple.com/documentation/storekit/storefront/updates)
- [Subscription Bundles and Suites](https://developer.apple.com/app-store/subscriptions/bundles-and-suites/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

Changes are availability guarded. Background scheduling, low-power policies and future runtime support are validated separately from compilation. No device OS, user's Xcode installation, VPN connection or existing App Store submission was updated by this audit.
