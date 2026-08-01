#!/usr/bin/env bash
# Build, publish and announce an Android release in one step.
#
# The update manifest's versionCode is read back out of the APK we actually
# built, never typed by hand — hand-maintaining it separately from
# pubspec.yaml let the two drift apart once, which silently stopped update
# prompts for anyone sitting on the in-between build.
#
# Usage: scripts/deploy-release.sh "Release notes shown in the update prompt."
set -euo pipefail

RELEASE_NOTES="${1:-Bug fixes and improvements.}"

API_BASE_URL="https://ourchat.safeshare.co"
SSH_KEY="C:\\Users\\user\\Downloads\\LightsailDefaultKey-ap-south-1.pem"
SSH_HOST="ubuntu@13.232.202.161"
REMOTE_ENV="/home/ubuntu/ourchat-backend/.env"
REMOTE_APK="/var/www/ourchat/downloads/ourchat.apk"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/app"
APK_PATH="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"

FLUTTER="${FLUTTER_BIN:-F:/flutter/bin/flutter.bat}"
AAPT2="$(find "$LOCALAPPDATA/Android/Sdk/build-tools" -maxdepth 2 -iname 'aapt2.exe' 2>/dev/null | sort -r | head -1)"
if [ -z "$AAPT2" ]; then
  echo "error: aapt2 not found; cannot verify the APK's versionCode" >&2
  exit 1
fi

echo "==> Building release APK against $API_BASE_URL"
(cd "$APP_DIR" && "$FLUTTER" build apk --release --dart-define=API_BASE_URL="$API_BASE_URL")

# Single source of truth: whatever the APK actually declares.
VERSION_CODE="$("$AAPT2" dump badging "$APK_PATH" | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p" | head -1)"
VERSION_NAME="$("$AAPT2" dump badging "$APK_PATH" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p" | head -1)"
if [ -z "$VERSION_CODE" ]; then
  echo "error: could not read versionCode from $APK_PATH" >&2
  exit 1
fi
echo "==> Built $VERSION_NAME (versionCode $VERSION_CODE)"

echo "==> Uploading APK"
scp -q -i "$SSH_KEY" "$APK_PATH" "$SSH_HOST:/tmp/ourchat.apk"

echo "==> Publishing and announcing versionCode $VERSION_CODE"
# Base64'd rather than interpolated into the remote command string directly —
# an apostrophe (or any other shell-special character) in free-text release
# notes previously broke the quoting and aborted the deploy mid-way.
RELEASE_NOTES_B64="$(printf '%s' "$RELEASE_NOTES" | base64 -w0)"
ssh -i "$SSH_KEY" "$SSH_HOST" \
  "VERSION_CODE='$VERSION_CODE' RELEASE_NOTES_B64='$RELEASE_NOTES_B64' bash -s" <<'REMOTE'
set -euo pipefail
sudo mv /tmp/ourchat.apk /var/www/ourchat/downloads/ourchat.apk
sudo chown www-data:www-data /var/www/ourchat/downloads/ourchat.apk

# Stripped of double-quotes and newlines rather than escaped: release notes
# are short marketing text, and this sidesteps ever having to match dotenv's
# exact unescaping rules for a value that isn't worth the risk.
RELEASE_NOTES="$(printf '%s' "$RELEASE_NOTES_B64" | base64 -d | tr -d '"\n\r')"

# Rewrite the keys outright rather than substituting the previous value, so
# this stays correct no matter what the file currently says.
sed -i '/^APP_VERSION_CODE=/d;/^APP_RELEASE_NOTES=/d' /home/ubuntu/ourchat-backend/.env
printf 'APP_VERSION_CODE=%s\n' "$VERSION_CODE" >> /home/ubuntu/ourchat-backend/.env
printf 'APP_RELEASE_NOTES="%s"\n' "$RELEASE_NOTES" >> /home/ubuntu/ourchat-backend/.env

pm2 restart ourchat-backend --update-env >/dev/null
REMOTE

echo "==> Verifying the published manifest matches the published APK"
sleep 2
ADVERTISED="$(curl -s --resolve ourchat.safeshare.co:443:13.232.202.161 "$API_BASE_URL/app-version")"
echo "    $ADVERTISED"
ADVERTISED_CODE="$(printf '%s' "$ADVERTISED" | sed -n 's/.*"versionCode":\([0-9]*\).*/\1/p')"
if [ "$ADVERTISED_CODE" != "$VERSION_CODE" ]; then
  echo "error: server advertises $ADVERTISED_CODE but the hosted APK is $VERSION_CODE" >&2
  exit 1
fi
echo "==> OK: hosting and advertising versionCode $VERSION_CODE"
