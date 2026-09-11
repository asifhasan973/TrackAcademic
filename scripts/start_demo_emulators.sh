#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || ifconfig | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1)
LAN_IP=${LAN_IP:-127.0.0.1}

export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk@17"

echo "======================================================="
echo " Starting Firebase Emulators on LAN ($LAN_IP)"
echo "======================================================="

# Start emulators with 0.0.0.0 host binding
firebase emulators:exec \
  --only auth,firestore,functions \
  --project trackacademic-c0d1c \
  "node scripts/seed_demo_accounts.mjs && echo && echo 'Emulators ready and seeded!' && echo 'Phone must be on same Wi-Fi as Mac ($LAN_IP)' && cat"
