#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

# Allow passing explicit IP or detect current Wi-Fi LAN IP
if [ -n "$1" ]; then
  LAN_IP="$1"
else
  LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || ifconfig | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1)
fi

LAN_IP=${LAN_IP:-127.0.0.1}

export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk@17"
export DEMO_BUILD="true"
export USE_FIREBASE_EMULATORS="true"

echo "======================================================="
echo " Building TrackAcademic Demo APK for LAN"
echo " Target Emulator Host: $LAN_IP"
echo "======================================================="

flutter build apk --release \
  --dart-define=USE_FIREBASE_EMULATORS=true \
  --dart-define=FIREBASE_EMULATOR_HOST="$LAN_IP"

# Name output trackacademic-demo.apk
cp "build/app/outputs/flutter-apk/app-release.apk" "build/app/outputs/flutter-apk/trackacademic-demo.apk"
cp "build/app/outputs/flutter-apk/app-release.apk" "$DIR/trackacademic-demo.apk"

echo "======================================================="
echo " Demo APK Built Successfully!"
echo " Primary Artifact: $DIR/trackacademic-demo.apk"
echo " Build Artifact: $DIR/build/app/outputs/flutter-apk/trackacademic-demo.apk"
echo " Size: $(du -h "$DIR/trackacademic-demo.apk" | awk '{print $1}')"
echo " Configured Emulator IP: $LAN_IP"
echo "======================================================="
