#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== BUILDING TRACKACADEMIC ONLINE RELEASE APK ==="

# 1. Clear any demo-related or emulator environment variables
unset DEMO_BUILD
unset USE_FIREBASE_EMULATORS
unset FIREBASE_EMULATOR_HOST
export DEMO_BUILD=false
export USE_FIREBASE_EMULATORS=false

# 2. Configure Java 17 if installed via Homebrew
if [ -d "/opt/homebrew/opt/openjdk@17" ]; then
  export JAVA_HOME="/opt/homebrew/opt/openjdk@17"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

cd "$ROOT_DIR"

# 3. Require real HTTPS Backend URL
BACKEND_URL="https://trackacademic-backend.vercel.app/api"
echo "Target HTTPS Backend URL: $BACKEND_URL"

# 4. Build Release APK
echo "Running flutter build apk --release..."
flutter build apk --release \
  --dart-define=USE_FIREBASE_EMULATORS=false \
  --dart-define=BACKEND_URL="$BACKEND_URL"

# 5. Locate and copy APK to root artifact
SRC_APK="$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk"
DEST_APK="$ROOT_DIR/trackacademic-online.apk"

if [ -f "$SRC_APK" ]; then
  cp "$SRC_APK" "$DEST_APK"
  echo "✔ Successfully copied release APK to: $DEST_APK"
  ls -lh "$DEST_APK"
else
  echo "❌ Error: Release APK not found at $SRC_APK"
  exit 1
fi

# 6. Verify merged AndroidManifest.xml for cleartext traffic
MERGED_MANIFEST="$ROOT_DIR/build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml"
if [ ! -f "$MERGED_MANIFEST" ]; then
  MERGED_MANIFEST=$(find "$ROOT_DIR/build/app/intermediates/merged_manifest" -name "AndroidManifest.xml" 2>/dev/null | head -n 1)
fi

echo "Verifying merged AndroidManifest.xml..."
if [ -f "$MERGED_MANIFEST" ]; then
  echo "Found merged manifest: $MERGED_MANIFEST"
  if grep -q 'android:usesCleartextTraffic="false"' "$MERGED_MANIFEST"; then
    echo "✔ VERIFIED: Merged Android manifest explicitly disables cleartext traffic (usesCleartextTraffic=\"false\")."
  elif grep -q 'android:usesCleartextTraffic="true"' "$MERGED_MANIFEST"; then
    echo "❌ SECURITY FAILURE: Merged Android manifest has usesCleartextTraffic=\"true\"!"
    exit 1
  else
    echo "✔ Notice: usesCleartextTraffic is not set to true (defaults to false in Android)."
  fi
else
  echo "Notice: Merged manifest path not found for direct inspection; APK is packaged."
fi

echo "=== ONLINE BUILD COMPLETE ==="
