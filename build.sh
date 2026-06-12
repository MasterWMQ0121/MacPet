#!/bin/zsh
# Builds MacPet.app next to this script.
set -e
cd "$(dirname "$0")"

APP=MacPet.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# universal binary: Apple Silicon + Intel, macOS 13+
swiftc -O -target arm64-apple-macos13 main.swift -o /tmp/MacPet-arm64
swiftc -O -target x86_64-apple-macos13 main.swift -o /tmp/MacPet-x86_64
lipo -create -output "$APP/Contents/MacOS/MacPet" /tmp/MacPet-arm64 /tmp/MacPet-x86_64
rm /tmp/MacPet-arm64 /tmp/MacPet-x86_64

cp pet0.png pet1.png pet_eat.png pet_sleep.png pet_sit.png pet_lie.png pet_lie2.png bubble.png "$APP/Contents/Resources/"
cp pet.svg "$APP/Contents/Resources/pet.svg"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>      <string>MacPet</string>
    <key>CFBundleIdentifier</key>      <string>local.mingqi.macpet</string>
    <key>CFBundleName</key>            <string>MacPet</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>LSUIElement</key>             <true/>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

# ad-hoc sign the whole bundle so the signature seals all resources
codesign --force --deep -s - "$APP"

if [ -d "/Applications/MacPet.app" ]; then
    rm -rf "/Applications/MacPet.app"
    ditto "$APP" "/Applications/MacPet.app"
    echo "Updated /Applications/MacPet.app"
fi

echo "Built $APP — launch with: open $APP"
