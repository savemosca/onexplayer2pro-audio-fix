#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FIX_SCRIPT="${FIX_SCRIPT:-$SCRIPT_DIR/oxp2p-audio-fix.sh}"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/oxp2p-audio-fix.env}"
RESUME_WAIT_SECONDS=15

load_env_file() {
    local key value

    while IFS='=' read -r key value; do
        case "$key" in
          ''|\#*)
            continue
            ;;
        esac

        case "$key" in
          EXPECTED_CODEC_VENDOR_PREFIX|EXPECTED_CODEC_VENDOR_IDS|EXPECTED_CODEC_SUBSYSTEM_IDS|EXPECTED_CODEC_NAME_PATTERN|ALLOW_UNSUPPORTED_CODEC)
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

if [ -f "$ENV_FILE" ]; then
    load_env_file
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

echo "Reapplying ONEXPLAYER 2 Pro audio fix after resume" >&2
if ! "$FIX_SCRIPT" -y -w "$RESUME_WAIT_SECONDS"; then
    echo "Unable to reapply ONEXPLAYER 2 Pro audio fix after resume" >&2
    exit 1
fi
