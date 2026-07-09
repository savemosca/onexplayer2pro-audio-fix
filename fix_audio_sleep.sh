#!/bin/bash

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FIX_SCRIPT="${FIX_SCRIPT:-$SCRIPT_DIR/oxp2p-audio-fix.sh}"
RESUME_WAIT_SECONDS=15

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
