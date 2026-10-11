#!/usr/bin/env bash
# Tests and builds release APKs (one per CPU type, to keep each under 50 MB).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/app"

if python3 -c "import json,sys; sys.exit(0 if json.load(open('assets/model/model_meta.json'))['is_demo'] else 1)"; then
  echo "WARNING: bundling the DEMO model. Results will not be meaningful." >&2
fi

flutter analyze
flutter test
flutter build apk --release --split-per-abi

# NFR1/NFR5: the release app must not request network, phone or storage access.
MERGED=$(find build/app/intermediates/merged_manifests/release -name AndroidManifest.xml | head -1)
for perm in INTERNET READ_PHONE_STATE READ_EXTERNAL_STORAGE WRITE_EXTERNAL_STORAGE; do
  if grep -q "android.permission.$perm\"" "$MERGED"; then
    echo "ERROR: release manifest requests $perm" >&2
    exit 1
  fi
done
echo "Release manifest requests no network, phone or storage permissions. Requested:"
grep -o '<uses-permission android:name="[^"]*"' "$MERGED" | sed -E 's/.*name="([^"]*)"/  \1/' || echo "  (none)"

ls -lh build/app/outputs/flutter-apk/*-release.apk
