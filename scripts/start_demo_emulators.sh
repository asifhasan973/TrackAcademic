#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || ifconfig | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1)
LAN_IP=${LAN_IP:-127.0.0.1}

export PATH="/opt/homebrew/bin:/opt/homebrew/opt/openjdk@17/bin:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk@17"

# Clean up only verified TrackAcademic emulator processes on emulator ports
for port in 9099 8080 5001 9199 4000 4400 4500; do
  for pid in $(lsof -ti :$port 2>/dev/null || true); do
    cmd=$(ps -p "$pid" -o command= 2>/dev/null || true)
    if echo "$cmd" | grep -qiE 'firebase|firestore|cloud-firestore|emulator'; then
      echo "Stopping verified emulator process $pid on port $port..."
      kill -9 "$pid" 2>/dev/null || true
    fi
  done
done

echo "======================================================="
echo " Starting Firebase Emulators on LAN ($LAN_IP)"
echo "======================================================="

# Start emulators with 0.0.0.0 host binding and seed
firebase emulators:exec \
  --only auth,firestore,functions \
  --project trackacademic-c0d1c \
  "node scripts/seed_demo_accounts.mjs && echo && echo '=======================================================' && echo ' Emulators ready & seeded!' && echo ' Connect physical phone to same Wi-Fi ($LAN_IP)' && echo ' Press Ctrl+C to stop emulators' && echo '=======================================================' && while true; do sleep 3600; done"
