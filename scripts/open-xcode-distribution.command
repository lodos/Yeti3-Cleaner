#!/bin/zsh
set -eu
# Apple's rsync starts a receiver using PATH. Homebrew rsync rejects
# Apple's --extended-attributes option during IPA packaging.
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
exec /usr/bin/open -n -a Xcode --env PATH=/usr/bin:/bin:/usr/sbin:/sbin "${1:-$ROOT/ios/Yeti3Cleaner.xcodeproj}"
