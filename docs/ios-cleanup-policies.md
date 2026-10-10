# iOS cleanup policies

Manual is the default: analyze -> select -> dry run -> confirm -> revalidate -> apply. Dry run never changes personal data. It reports logical size, not guaranteed immediately reclaimed storage. Plans expire after 15 minutes and reject changed selections or scans. Exact duplicate groups retain at least one member, favorites and unavailable originals are excluded. File deletion validates path, modification date and streamed SHA-256 again; duplicate survivors must still exist unchanged. Photo deletion rechecks Photos content. Contacts are edited exclusively through the system editor.

Automatic analysis is opt-in. On foreground activation it checks the chosen minimum interval (6/24/168 hours), power connection, battery threshold, Low Power Mode and thermal state. It only uses previously granted access and session-selected files; it does not issue permission prompts, download iCloud originals, select personal files for deletion or delete them. Attempts are timestamped before starting to avoid rapid failure/retry loops. Backgrounding cancels the scan; incomplete reports cannot authorize deletion. iOS does not guarantee timers in a suspended app; no such guarantee is advertised.

Users can separately customize every strategy, category, screenshot age, large-file threshold and optimization quality. JPEG optimization preserves originals and removes EXIF/location metadata. Saving a copy initially consumes storage.

Verification: 16 unit tests passed, including changed files, missing duplicate survivor, symlink replacement, unknown selection, stale dry runs, battery/power/thermal gating, malformed images and metadata stripping. One UI capture test passed on iPad; iPhone capture also passed. This does not replace a physical-device test of PhotoKit deletion/iCloud/provider behavior.

macOS preserves the existing Rust/AppKit client and its explicit dry-run plan/consent rules; it is not replaced by the iOS implementation. Existing native release is ad-hoc signed. App Store/TestFlight requires a real sandbox access migration, plus distribution signing. Never claim the unrestricted cleaner is already sandbox-compatible.
