#!/bin/bash
set -euo pipefail

DEFAULT_INSTALL_DIR="/home/bazzite/oxp2p-audio-fix"
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
SERVICE_PATH="/etc/systemd/system/fix_audio.service"
SLEEP_HOOK_PATH="/etc/systemd/system-sleep/oxp2p-audio-fix"
START_SERVICE=1

usage() {
    echo "Usage: sudo $0 [--install-dir DIR] [--no-start]" >&2
    echo "  --install-dir DIR  Install runtime files into DIR (default: $DEFAULT_INSTALL_DIR)" >&2
    echo "  --no-start         Install and enable the service, but do not start it now" >&2
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
      --no-start)
        START_SERVICE=0
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

case "$INSTALL_DIR" in
  *[[:space:]]*)
    echo "Install directory must not contain whitespace: $INSTALL_DIR" >&2
    exit 64
    ;;
esac

if [ "$(id -u)" -ne 0 ]; then
    echo "This installer must be run as root. Try: sudo $0" >&2
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl is required but was not found." >&2
    exit 2
fi

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

for file in oxp2p-audio-fix.sh fix_audio_sleep.sh install.sh uninstall.sh README.md; do
    if [ ! -f "$SCRIPT_DIR/$file" ]; then
        echo "Required file is missing from source directory: $file" >&2
        exit 2
    fi
done

copy_file() {
    local src=$1
    local dest=$2
    local mode=$3

    if [ -e "$dest" ] && [ "$(realpath "$src")" = "$(realpath "$dest")" ]; then
        chmod "$mode" "$dest"
    else
        install -m "$mode" "$src" "$dest"
    fi
}

write_service() {
    {
        printf '[Unit]\n'
        printf 'Description=Fix audio on the OneXplayer 2 Pro\n'
        printf 'After=sound.target\n'
        printf 'Requires=sound.target\n'
        printf '\n'
        printf '[Service]\n'
        printf 'Type=oneshot\n'
        printf 'ExecStart=%s/oxp2p-audio-fix.sh -y -w 30\n' "$INSTALL_DIR"
        printf 'RemainAfterExit=true\n'
        printf '\n'
        printf '[Install]\n'
        printf 'WantedBy=multi-user.target\n'
    } > "$SERVICE_PATH"
    chmod 0644 "$SERVICE_PATH"
}

write_sleep_hook() {
    {
        printf '#!/bin/bash\n'
        printf '\n'
        printf 'exec "%s/fix_audio_sleep.sh" "$@"\n' "$INSTALL_DIR"
    } > "$SLEEP_HOOK_PATH"
    chmod 0755 "$SLEEP_HOOK_PATH"
}

mkdir -p "$INSTALL_DIR"
mkdir -p "$(dirname -- "$SERVICE_PATH")"
mkdir -p "$(dirname -- "$SLEEP_HOOK_PATH")"

copy_file "$SCRIPT_DIR/oxp2p-audio-fix.sh" "$INSTALL_DIR/oxp2p-audio-fix.sh" 0755
copy_file "$SCRIPT_DIR/fix_audio_sleep.sh" "$INSTALL_DIR/fix_audio_sleep.sh" 0755
copy_file "$SCRIPT_DIR/install.sh" "$INSTALL_DIR/install.sh" 0755
copy_file "$SCRIPT_DIR/uninstall.sh" "$INSTALL_DIR/uninstall.sh" 0755
copy_file "$SCRIPT_DIR/README.md" "$INSTALL_DIR/README.md" 0644

write_service
write_sleep_hook

systemctl daemon-reload
systemctl enable fix_audio.service

if [ "$START_SERVICE" -eq 1 ]; then
    if command -v hda-verb >/dev/null 2>&1; then
        systemctl restart fix_audio.service
    else
        echo "hda-verb was not found, so the service was enabled but not started." >&2
        echo "Install alsa-tools with: sudo rpm-ostree install alsa-tools" >&2
        echo "Then reboot and run: sudo systemctl restart fix_audio.service" >&2
    fi
fi

echo "Installed ONEXPLAYER 2 Pro audio fix into: $INSTALL_DIR"
echo "Installed systemd service: $SERVICE_PATH"
echo "Installed resume hook: $SLEEP_HOOK_PATH"
