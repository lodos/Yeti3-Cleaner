# YETI3-Cleaner — application assets

The app icons are included in the checked-in Xcode projects. App Store screenshots are publication assets and are intentionally not bundled into the runtime app.

Run `python3 scripts/build-asset-pack.py` from the repository root to reproduce the public archive. The archive contains only tracked artwork, icon catalogs, theme files and screenshots; no signing keys, credentials, provisioning profiles or user files.

Every file is listed with SHA-256 in manifest.json.
