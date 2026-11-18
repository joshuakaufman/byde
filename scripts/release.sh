#!/bin/zsh
# Usage: scripts/release.sh <version>   e.g. scripts/release.sh 1.0
# Writes the version into build.sh (and bumps the build number), builds and ad-hoc signs Byde.app,
# then makes dist/<version>/Byde-<version>.dmg and prints its SHA-256.
set -e
cd "$(dirname "$0")/.."
V=$1
[[ $V =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "usage: $0 <version>   (e.g. 1.2 or 1.2.1; got '$V')"; exit 1; }
[[ ! -e dist/$V ]] || { echo "dist/$V already exists. A released version is never rebuilt."; exit 1; }
git rev-parse -q --verify "refs/tags/v$V" >/dev/null && { echo "Tag v$V already exists. A released version is never rebuilt."; exit 1; }
BUILD=$(( $(sed -n 's|.*<key>CFBundleVersion</key><string>\([0-9]*\)</string>.*|\1|p' build.sh) + 1 ))
sed -i '' -e "s|\(<key>CFBundleShortVersionString</key><string>\)[^<]*|\1$V|" \
          -e "s|\(<key>CFBundleVersion</key><string>\)[^<]*|\1$BUILD|" build.sh
./build.sh                                   # release build, ad-hoc signed
codesign --verify --strict Byde.app
OUT=dist/$V
STAGE=$(mktemp -d)
rm -rf "$OUT" && mkdir -p "$OUT"
cp -R Byde.app "$STAGE/" && ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Byde $V" -srcfolder "$STAGE" -ov -format UDZO "$OUT/Byde-$V.dmg" >/dev/null
rm -rf "$STAGE"
echo "Version $V (build $BUILD)"
shasum -a 256 "$OUT/Byde-$V.dmg"
