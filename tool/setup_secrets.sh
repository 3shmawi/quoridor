#!/usr/bin/env bash
# Pushes this repo's release secrets to GitHub, from one folder on your Mac.
#
#   tool/setup_secrets.sh            set every secret that has a value
#   tool/setup_secrets.sh --dry-run  show what would be set, change nothing
#
# Values shared by all your apps live in ~/.app-secrets/shared.env (made as a
# template on the first run). Values that belong to one app -- its Android
# upload keystore and passwords -- live in ~/.app-secrets/apps/<repo>/ and are
# generated the first time, with a random password. This app's Firebase
# service account key, which only you can create, goes in that folder too, as
# firebase-service-account.json. Set APP_SECRETS_DIR to keep the folder
# elsewhere.
#
# Needs: gh (logged in), keytool (any JDK), openssl. Secret values are piped
# to gh on stdin, never passed as arguments or printed.
set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

DIR="${APP_SECRETS_DIR:-$HOME/.app-secrets}"
SHARED="$DIR/shared.env"

die() { echo "setup_secrets: $*" >&2; exit 1; }
for tool in gh keytool openssl; do
  command -v "$tool" >/dev/null || die "$tool is not installed"
done

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner) ||
  die "run this inside a GitHub repo, after 'gh auth login'"
APP_DIR="$DIR/apps/${REPO#*/}"

umask 077
mkdir -p "$DIR" "$APP_DIR"

# --- Shared values: written once as a template, filled in by hand ----------
if [[ ! -f "$SHARED" ]]; then
  cat > "$SHARED" <<'TEMPLATE'
# Values every app shares. Paths may use ~. Leave a value empty to skip
# the secrets that need it; the release workflow then skips that job.

# Apple (developer.apple.com -> Membership)
APPLE_TEAM_ID=

# App Store Connect API key (Users and Access -> Integrations -> Keys)
ASC_KEY_ID=
ASC_ISSUER_ID=
ASC_KEY_P8_PATH=~/.app-secrets/AuthKey_XXXXXXXXXX.p8

# Apple Distribution certificate, exported from Keychain as .p12 (iOS)
IOS_CERTIFICATE_P12_PATH=~/.app-secrets/ios_distribution.p12
IOS_CERTIFICATE_PASSWORD=

# Developer ID Application certificate as .p12 (macOS outside the store)
MACOS_DEVELOPER_ID_P12_PATH=~/.app-secrets/developer_id.p12
MACOS_DEVELOPER_ID_P12_PASSWORD=

# Google Play service account JSON (one per developer account)
PLAY_SERVICE_ACCOUNT_JSON_PATH=~/.app-secrets/play-service-account.json

# Fine-grained GitHub token with Contents: write, so a bump tag starts the
# release. One token can cover all your repos.
RELEASE_TOKEN=

# itch.io API key (itch.io -> Settings -> API keys), for pushing releases
BUTLER_API_KEY=

# Cloudflare API token with only "Cloudflare Pages: Edit", for the web deploy
CLOUDFLARE_API_TOKEN=

# Who new Android keystores are issued to
KEYSTORE_DNAME="CN=Your Name, O=Your Company, C=EG"
TEMPLATE
  echo "Created $SHARED -- fill it in, then run this again."
  exit 0
fi

# shellcheck disable=SC1090
source "$SHARED"
expand() { local p="${1:-}"; echo "${p/#\~/$HOME}"; }

# --- Per-app Android keystore: generated once, then reused -----------------
KEYSTORE="$APP_DIR/upload.jks"
APP_ENV="$APP_DIR/app.env"
if [[ ! -f "$KEYSTORE" ]]; then
  PASSWORD=$(openssl rand -base64 24 | tr -d '/+=')
  if $DRY_RUN; then
    echo "would create   $KEYSTORE (alias upload, random password)"
  else
    keytool -genkeypair -v -storetype JKS -keyalg RSA -keysize 2048 \
      -validity 10000 -alias upload -keystore "$KEYSTORE" \
      -storepass "$PASSWORD" -keypass "$PASSWORD" \
      -dname "${KEYSTORE_DNAME:-CN=Android Upload}" >/dev/null 2>&1
    printf 'ANDROID_KEY_ALIAS=upload\nANDROID_STORE_PASSWORD=%s\nANDROID_KEY_PASSWORD=%s\n' \
      "$PASSWORD" "$PASSWORD" > "$APP_ENV"
    echo "created       $KEYSTORE -- back this folder up; Play needs the same key for every update"
  fi
fi
# shellcheck disable=SC1090
[[ -f "$APP_ENV" ]] && source "$APP_ENV"

# --- Push ------------------------------------------------------------------
set_value() { # name value
  local name=$1 value=${2:-}
  if [[ -z "$value" ]]; then echo "skip          $name (no value)"; return; fi
  if $DRY_RUN; then echo "would set     $name"; return; fi
  printf '%s' "$value" | gh secret set "$name" --repo "$REPO" >/dev/null
  echo "set           $name"
}

set_file() { # name path [base64]
  local name=$1 path encode=${3:-}
  path=$(expand "${2:-}")
  if [[ -z "$path" || ! -f "$path" ]]; then echo "skip          $name (no file${path:+ at $path})"; return; fi
  if $DRY_RUN; then echo "would set     $name from $path"; return; fi
  if [[ -n "$encode" ]]; then
    base64 < "$path" | tr -d '\n' | gh secret set "$name" --repo "$REPO" >/dev/null
  else
    gh secret set "$name" --repo "$REPO" < "$path" >/dev/null
  fi
  echo "set           $name"
}

echo "Repo: $REPO"
set_file  ANDROID_KEYSTORE_BASE64          "$KEYSTORE" base64
set_value ANDROID_KEY_ALIAS                "${ANDROID_KEY_ALIAS:-}"
set_value ANDROID_STORE_PASSWORD           "${ANDROID_STORE_PASSWORD:-}"
set_value ANDROID_KEY_PASSWORD             "${ANDROID_KEY_PASSWORD:-}"
set_file  PLAY_SERVICE_ACCOUNT_JSON        "${PLAY_SERVICE_ACCOUNT_JSON_PATH:-}"
set_value APPLE_TEAM_ID                    "${APPLE_TEAM_ID:-}"
set_value ASC_KEY_ID                       "${ASC_KEY_ID:-}"
set_value ASC_ISSUER_ID                    "${ASC_ISSUER_ID:-}"
set_file  ASC_KEY_P8_BASE64                "${ASC_KEY_P8_PATH:-}" base64
set_file  IOS_CERTIFICATE_P12_BASE64       "${IOS_CERTIFICATE_P12_PATH:-}" base64
set_value IOS_CERTIFICATE_PASSWORD         "${IOS_CERTIFICATE_PASSWORD:-}"
set_file  MACOS_DEVELOPER_ID_P12_BASE64    "${MACOS_DEVELOPER_ID_P12_PATH:-}" base64
set_value MACOS_DEVELOPER_ID_P12_PASSWORD  "${MACOS_DEVELOPER_ID_P12_PASSWORD:-}"
set_value RELEASE_TOKEN                    "${RELEASE_TOKEN:-}"
set_value BUTLER_API_KEY                   "${BUTLER_API_KEY:-}"
set_value CLOUDFLARE_API_TOKEN             "${CLOUDFLARE_API_TOKEN:-}"
set_file  FIREBASE_SERVICE_ACCOUNT_JSON    "$APP_DIR/firebase-service-account.json"
