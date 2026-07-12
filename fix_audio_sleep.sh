#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FIX_SCRIPT="${FIX_SCRIPT:-$SCRIPT_DIR/oxp2p-audio-fix.sh}"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/oxp2p-audio-fix.env}"
RESUME_WAIT_SECONDS="${RESUME_WAIT_SECONDS:-30}"
RESUME_SETTLE_SECONDS="${RESUME_SETTLE_SECONDS:-3}"
RESUME_REAPPLY_COUNT="${RESUME_REAPPLY_COUNT:-2}"
RESUME_REAPPLY_INTERVAL_SECONDS="${RESUME_REAPPLY_INTERVAL_SECONDS:-2}"

load_env_file() {
    local key value

    while IFS='=' read -r key value; do
        case "$key" in
          ''|\#*)
            continue
            ;;
        esac

        case "$key" in
          EXPECTED_CODEC_VENDOR_PREFIX|EXPECTED_CODEC_VENDOR_IDS|EXPECTED_CODEC_SUBSYSTEM_IDS|EXPECTED_CODEC_NAME_PATTERN|ALLOW_UNSUPPORTED_CODEC|FIX_SENTINEL_COEFS|RESUME_WAIT_SECONDS|RESUME_SETTLE_SECONDS|RESUME_REAPPLY_COUNT|RESUME_REAPPLY_INTERVAL_SECONDS)
            ;;
          *)
            continue
            ;;
        esac

        case "$value" in
          \"*\")
            value=${value#\"}
            value=${value%\"}
            ;;
        esac

        export "$key=$value"
    done < "$ENV_FILE"
}

require_integer() {
    local name=$1
    local value=$2

    case "$value" in
      ''|*[!0-9]*)
        echo "$name must be a non-negative integer: $value" >&2
        exit 64
        ;;
    esac
}

if [ -f "$ENV_FILE" ]; then
    load_env_file
fi

require_integer RESUME_WAIT_SECONDS "$RESUME_WAIT_SECONDS"
require_integer RESUME_SETTLE_SECONDS "$RESUME_SETTLE_SECONDS"
require_integer RESUME_REAPPLY_COUNT "$RESUME_REAPPLY_COUNT"
require_integer RESUME_REAPPLY_INTERVAL_SECONDS "$RESUME_REAPPLY_INTERVAL_SECONDS"

if [ "$RESUME_REAPPLY_COUNT" -lt 1 ]; then
    echo "RESUME_REAPPLY_COUNT must be at least 1: $RESUME_REAPPLY_COUNT" >&2
    exit 64
fi

case "${1:-}" in
  post)
    ;;
  *)
    exit 0
    ;;
esac

case "${2:-}" in
  suspend|hibernate|hybrid-sleep|suspend-then-hibernate|'')
    ;;
  *)
    exit 0
    ;;
esac

if [ ! -x "$FIX_SCRIPT" ]; then
    echo "Audio fix script is missing or not executable: $FIX_SCRIPT" >&2
    exit 1
fi

if [ "$RESUME_SETTLE_SECONDS" -gt 0 ]; then
    echo "Waiting ${RESUME_SETTLE_SECONDS}s for audio hardware to settle after resume" >&2
    sleep "$RESUME_SETTLE_SECONDS"
fi

run_check() {
    "$FIX_SCRIPT" -c -w "$RESUME_WAIT_SECONDS"
}

apply_fix() {
    "$FIX_SCRIPT" -y -k -w "$RESUME_WAIT_SECONDS"
}

reapply_blindly() {
    local attempt=1

    while [ "$attempt" -le "$RESUME_REAPPLY_COUNT" ]; do
        echo "Reapplying ONEXPLAYER 2 Pro audio fix after resume ($attempt/$RESUME_REAPPLY_COUNT)" >&2
        if ! apply_fix; then
            echo "Unable to reapply ONEXPLAYER 2 Pro audio fix after resume" >&2
            exit 1
        fi

        if [ "$attempt" -lt "$RESUME_REAPPLY_COUNT" ] && [ "$RESUME_REAPPLY_INTERVAL_SECONDS" -gt 0 ]; then
            sleep "$RESUME_REAPPLY_INTERVAL_SECONDS"
        fi

        attempt=$((attempt + 1))
    done
}

check_rc=0
run_check || check_rc=$?

if [ "$check_rc" -eq 7 ]; then
    # No sentinel coefficients configured: fall back to blind reapplication.
    reapply_blindly
    exit 0
fi

if [ "$check_rc" -eq 0 ]; then
    echo "Audio fix already verified after resume; nothing to reapply." >&2
    exit 0
fi

attempt=1
while [ "$attempt" -le "$RESUME_REAPPLY_COUNT" ]; do
    echo "Applying ONEXPLAYER 2 Pro audio fix after resume ($attempt/$RESUME_REAPPLY_COUNT)" >&2

    apply_rc=0
    apply_fix || apply_rc=$?
    case "$apply_rc" in
      0)
        ;;
      6)
        echo "Sentinel verification failed right after applying; will re-check." >&2
        ;;
      *)
        echo "Unable to reapply ONEXPLAYER 2 Pro audio fix after resume" >&2
        exit 1
        ;;
    esac

    if [ "$RESUME_REAPPLY_INTERVAL_SECONDS" -gt 0 ]; then
        sleep "$RESUME_REAPPLY_INTERVAL_SECONDS"
    fi

    check_rc=0
    run_check || check_rc=$?
    if [ "$check_rc" -eq 0 ]; then
        echo "Audio fix verified after resume (attempt $attempt/$RESUME_REAPPLY_COUNT)." >&2
        exit 0
    fi

    attempt=$((attempt + 1))
done

echo "Audio fix could not be verified after $RESUME_REAPPLY_COUNT attempt(s) following resume." >&2
exit 1
