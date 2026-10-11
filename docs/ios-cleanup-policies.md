# Cleaner safety and automation

Analyze → select → review the dry run → explicitly confirm → revalidate → apply. Logical sizes do not guarantee immediate reclaimed space. Plans expire after 15 minutes and reject changed selections, changed scans and unknown objects. Changing a scan profile invalidates results and selections.

Exact duplicate groups retain at least one unchanged accessible member. Favorites, protected recent/undated photos, unavailable originals and (by default) burst representatives cannot be selected. Files are checked again for path boundaries, symbolic links, modification time and streamed SHA-256. PhotoKit content is revalidated. Contacts are edited only through the system editor. No personal data is silently deleted.

Three independent profiles expose 38 scan options. File rules include allowed/excluded extensions, excluded child-folder names, recursion depth, age, minimum/maximum size, archives and object/time limits. Date filters with unknown dates fail closed. Photos include period, video thresholds, screenshot age and similarity settings. JPEG copies preserve originals and remove EXIF/location; RAW, HDR, Live, spatial, panorama and edited assets are excluded. Creating a copy initially consumes additional storage.

Automatic foreground analysis uses only already authorized data, selected session files, frequency, charging, battery, Low Power Mode and thermal checks. It never opens permission sheets for a new category. Without a continued task, backgrounding cancels deep analysis; incomplete reports cannot authorize deletion.

On iOS 26+, explicit manual analysis can opt in to Continued Processing. The system displays progress/cancel. Requests are never queued; if refused, analysis stays foreground-only. Expiration/user cancellation cancels the same worker. It retains all time/object/heat limits and does not authorize deletion. System APIs and file providers can delay cooperative cancellation; no hard real-time guarantee is made.

Separately opt-in BGProcessing only enumerates metadata of up to 250 recent Photos assets, with a cooperative 10-second budget, no hashing/network/deletion. iOS selects the launch time. iOS 27 uses the async scheduler submission API.

Full native Mac keeps its Rust engine and explicit cleanup plans. Its new opt-in overview reads at most 250 top-level entries of a user-selected local directory with a cooperative 10-second budget and 20-ms pacing. One shared scheduler, minimum 6 hours, optional AC and battery threshold; Low Power Mode or non-nominal thermal state stops work. Nested folders, symlinks and non-local volumes are not traversed. The overview never invokes the cleanup engine or modifies a deletion plan. It works while the native Cleaner process is running, and does not install an agent or wake a sleeping Mac.

Mac Catalyst is the sandboxed store candidate with selected-folder and personal-library access. The full native package is a separate direct distribution; system cache cleanup is not claimed for the sandboxed build. Both have a macOS 14 deployment target and universal binaries. Intel runtime and notarization remain separate acceptance gates.

See `ios/Release/verification-2026-10-11.txt` and `docs/apple-compatibility-2026-10-11.md` for evidence and unresolved checks. Real personal PhotoKit deletion, File Provider/iCloud behavior, live payments and energy results are not inferred from unit tests.
