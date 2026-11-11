#!/bin/zsh
# Builds Byde.app next to this script. Usage: ./build.sh [run]
set -e
cd "$(dirname "$0")"
swift build -c release
APP=Byde.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS
cp .build/release/Byde $APP/Contents/MacOS/Byde
# App icon: the committed PNGs become AppIcon.icns (iconutil ships with macOS).
mkdir -p $APP/Contents/Resources .build/AppIcon.iconset
cp -f Assets.xcassets/AppIcon.appiconset/*.png .build/AppIcon.iconset/
iconutil -c icns .build/AppIcon.iconset -o $APP/Contents/Resources/AppIcon.icns
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.joshuakaufman.byde</string>
<key>CFBundleName</key><string>Byde</string>
<key>CFBundleExecutable</key><string>Byde</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - $APP
[[ "$1" == run ]] && open $APP
echo "Built $PWD/$APP"
