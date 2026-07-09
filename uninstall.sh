#!/bin/bash
set -euo pipefail

DEFAULT_INSTALL_DIR="/home/bazzite/oxp2p-audio-fix"
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
SERVICE_PATH="/etc/systemd/system/fix_audio.service"
SLEEP_HOOK_PATH="/etc/systemd/system-sleep/oxp2p-audio-fix"
KEEP_FILES=0

usage() {
    echo "Usage: sudo $0 [--install-dir DIR] [--keep-files]" >&2
    echo "  --install-dir DIR  Remove runtime files from DIR (default: $DEFAULT_INSTALL_DIR)" >&2
    echo "  --keep-files       Remove systemd integration only; keep files in install dir" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
      --install-dir)
        if [ "$#" -lt 2 ]; then
            usage
            exit 64
        fi
        INSTALL_DIR=$2
        shift 2
        ;;
      --keep-files)
        KEEP_FILES=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage
        exit 64
        ;;
    esac
done

case "$INSTALL_DIR" in
  /*)
    ;;
  *)
    echo "Install directory must be an absolute path: $INSTALL_DIR" >&2
    exit 64
    ;;
esac

if [ "$(id -u)" -ne 0 ]; then
    echo "This uninstaller must be run as root. Try: sudo $0" >&2
    exit 1
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now fix_audio.service >/dev/null 2>&1 || true
fi

rm -f "$SERVICE_PATH"
rm -f "$SLEEP_HOOK_PATH"

if [ "$KEEP_FILES" -ne 1 ]; then
    rm -f "$INSTALL_DIR/oxp2p-audio-fix.sh"
    rm -f "$INSTALL_DIR/fix_audio_sleep.sh"
    rm -f "$INSTALL_DIR/install.sh"
    rm -f "$INSTALL_DIR/uninstall.sh"
    rm -f "$INSTALL_DIR/README.md"

    if [ -d "$INSTALL_DIR" ]; then
        rmdir "$INSTALL_DIR" 2>/dev/null || {
            echo "Install directory was left in place because it is not empty: $INSTALL_DIR" >&2
        }
    fi
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl reset-failed fix_audio.service >/dev/null 2>&1 || true
fi

echo "Uninstalled ONEXPLAYER 2 Pro audio fix systemd integration."
