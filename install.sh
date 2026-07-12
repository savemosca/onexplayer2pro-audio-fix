#!/bin/bash
set -euo pipefail

DEFAULT_INSTALL_DIR="/usr/local/lib/oxp2p-audio-fix"
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
SERVICE_PATH="/etc/systemd/system/fix_audio.service"
SLEEP_HOOK_PATH="/etc/systemd/system-sleep/oxp2p-audio-fix"
POWER_SAVE_CONF_PATH="/etc/modprobe.d/oxp2p-audio-fix-power-save.conf"
MARKER_NAME=".oxp2p-audio-fix-installed"
START_SERVICE=0
ALLOW_RISKY_INSTALL_DIR=0
DISABLE_HDA_POWER_SAVE=0
CODEC_VENDOR_PREFIX="${EXPECTED_CODEC_VENDOR_PREFIX:-0x10ec}"
CODEC_VENDOR_IDS="${EXPECTED_CODEC_VENDOR_IDS:-}"
CODEC_SUBSYSTEM_IDS="${EXPECTED_CODEC_SUBSYSTEM_IDS:-}"
CODEC_NAME_PATTERN="${EXPECTED_CODEC_NAME_PATTERN:-Realtek}"

usage() {
    echo "Usage: sudo $0 [--install-dir DIR] [--start-now] [codec checks]" >&2
    echo "  --install-dir DIR  Install runtime files into DIR (default: $DEFAULT_INSTALL_DIR)" >&2
    echo "  --start-now        Install, enable, and start the service immediately" >&2
    echo "  --no-start         Install and enable the service without starting it now (default)" >&2
    echo "  --codec-vendor-id ID       Require an exact codec Vendor Id; can be passed multiple times" >&2
    echo "  --codec-subsystem-id ID    Require an exact codec Subsystem Id; can be passed multiple times" >&2
    echo "  --codec-vendor-prefix HEX  Require a Vendor Id prefix when no exact ids are set (default: $CODEC_VENDOR_PREFIX)" >&2
    echo "  --codec-name-pattern TEXT  Require codec name to contain TEXT (default: $CODEC_NAME_PATTERN)" >&2
    echo "  --disable-hda-power-save   Keep the HDA codec powered so the fix is not lost when it idles" >&2
    echo "  --allow-risky-install-dir  Allow install paths under home or temporary directories" >&2
}

append_list_value() {
    local list=$1
    local value=$2

    if [ -n "$list" ]; then
        printf '%s %s' "$list" "$value"
    else
        printf '%s' "$value"
    fi
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
      --start-now)
        START_SERVICE=1
        shift
        ;;
      --no-start)
        START_SERVICE=0
        shift
        ;;
      --codec-vendor-id)
        if [ "$#" -lt 2 ]; then
            usage
            exit 64
        fi
        CODEC_VENDOR_IDS=$(append_list_value "$CODEC_VENDOR_IDS" "$2")
        shift 2
        ;;
      --codec-subsystem-id)
        if [ "$#" -lt 2 ]; then
            usage
            exit 64
        fi
        CODEC_SUBSYSTEM_IDS=$(append_list_value "$CODEC_SUBSYSTEM_IDS" "$2")
        shift 2
        ;;
      --codec-vendor-prefix)
        if [ "$#" -lt 2 ]; then
            usage
            exit 64
        fi
        CODEC_VENDOR_PREFIX=$2
        shift 2
        ;;
      --codec-name-pattern)
        if [ "$#" -lt 2 ]; then
            usage
            exit 64
        fi
        CODEC_NAME_PATTERN=$2
        shift 2
        ;;
      --disable-hda-power-save)
        DISABLE_HDA_POWER_SAVE=1
        shift
        ;;
      --allow-risky-install-dir)
        ALLOW_RISKY_INSTALL_DIR=1
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

require_hex_id() {
    local label=$1
    local value=$2

    case "$value" in
      0x*)
        case "${value#0x}" in
          '')
            ;;
          *[!0-9a-fA-F]*)
            ;;
          *)
            return 0
            ;;
        esac
        ;;
    esac

    echo "$label must be a hex id like 0x10ec0257: $value" >&2
    exit 64
}

require_hex_id "codec vendor prefix (--codec-vendor-prefix)" "$CODEC_VENDOR_PREFIX"

for codec_id in $CODEC_VENDOR_IDS; do
    require_hex_id "codec vendor id (--codec-vendor-id)" "$codec_id"
done

for codec_id in $CODEC_SUBSYSTEM_IDS; do
    require_hex_id "codec subsystem id (--codec-subsystem-id)" "$codec_id"
done

# The codec name pattern ends up in the generated env file, which is parsed
# both by systemd (EnvironmentFile=) and by fix_audio_sleep.sh; keep it to
# characters both parsers treat identically.
case "$CODEC_NAME_PATTERN" in
  '')
    echo "Codec name pattern (--codec-name-pattern) must not be empty." >&2
    exit 64
    ;;
  *'"'*|*\\*|*'$'*|*'`'*|*'='*|*$'\n'*|*$'\r'*)
    echo "Codec name pattern (--codec-name-pattern) must not contain quotes, backslashes, dollar signs, backticks, '=' or newlines: $CODEC_NAME_PATTERN" >&2
    exit 64
    ;;
esac

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

case "$INSTALL_DIR" in
  /|/usr|/usr/local|/usr/local/lib|/opt|/etc|/var|/home|/tmp|/var/tmp|/run|/run/user)
    echo "Install directory is too broad: $INSTALL_DIR" >&2
    exit 64
    ;;
esac

case "$INSTALL_DIR" in
  /home/*|/root/*|/tmp/*|/var/tmp/*|/run/user/*|/Users/*)
    if [ "$ALLOW_RISKY_INSTALL_DIR" -ne 1 ]; then
        echo "Refusing risky install directory: $INSTALL_DIR" >&2
        echo "Use a root-owned system path such as $DEFAULT_INSTALL_DIR, or pass --allow-risky-install-dir explicitly." >&2
        exit 64
    fi
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
ENV_PATH="$INSTALL_DIR/oxp2p-audio-fix.env"
MARKER_PATH="$INSTALL_DIR/$MARKER_NAME"

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
        chown root:root "$dest"
    else
        install -o root -g root -m "$mode" "$src" "$dest"
    fi
}

write_env_file() {
    {
        printf '# Generated by oxp2p-audio-fix install.sh\n'
        printf 'EXPECTED_CODEC_VENDOR_PREFIX="%s"\n' "$CODEC_VENDOR_PREFIX"
        printf 'EXPECTED_CODEC_VENDOR_IDS="%s"\n' "$CODEC_VENDOR_IDS"
        printf 'EXPECTED_CODEC_SUBSYSTEM_IDS="%s"\n' "$CODEC_SUBSYSTEM_IDS"
        printf 'EXPECTED_CODEC_NAME_PATTERN="%s"\n' "$CODEC_NAME_PATTERN"
        printf 'ALLOW_UNSUPPORTED_CODEC="0"\n'
        printf 'RESUME_WAIT_SECONDS="30"\n'
        printf 'RESUME_SETTLE_SECONDS="3"\n'
        printf 'RESUME_REAPPLY_COUNT="2"\n'
        printf 'RESUME_REAPPLY_INTERVAL_SECONDS="2"\n'
    } > "$ENV_PATH"
    chmod 0644 "$ENV_PATH"
    chown root:root "$ENV_PATH"
}

write_marker() {
    {
        printf 'version=1\n'
        printf 'install_dir=%s\n' "$INSTALL_DIR"
        printf 'service_path=%s\n' "$SERVICE_PATH"
        printf 'sleep_hook_path=%s\n' "$SLEEP_HOOK_PATH"
    } > "$MARKER_PATH"
    chmod 0644 "$MARKER_PATH"
    chown root:root "$MARKER_PATH"
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
        printf 'EnvironmentFile=-%s\n' "$ENV_PATH"
        printf 'ExecStart=%s/oxp2p-audio-fix.sh -y -k -w 30\n' "$INSTALL_DIR"
        printf 'RemainAfterExit=true\n'
        printf 'NoNewPrivileges=true\n'
        printf 'PrivateTmp=true\n'
        if [ "$ALLOW_RISKY_INSTALL_DIR" -eq 0 ]; then
            printf 'ProtectHome=true\n'
        fi
        printf 'ProtectSystem=full\n'
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

write_power_save_conf() {
    {
        printf '# Generated by oxp2p-audio-fix install.sh\n'
        printf '# Keep the HDA codec powered so the audio fix is not lost when it idles.\n'
        printf 'options snd_hda_intel power_save=0 power_save_controller=N\n'
    } > "$POWER_SAVE_CONF_PATH"
    chmod 0644 "$POWER_SAVE_CONF_PATH"
    chown root:root "$POWER_SAVE_CONF_PATH"

    # Apply immediately when the module is already loaded; the modprobe.d
    # file only takes effect on the next boot.
    if [ -e /sys/module/snd_hda_intel/parameters/power_save ]; then
        printf '0\n' > /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null || true
    fi
    if [ -e /sys/module/snd_hda_intel/parameters/power_save_controller ]; then
        printf 'N\n' > /sys/module/snd_hda_intel/parameters/power_save_controller 2>/dev/null || true
    fi
}

install -d -o root -g root -m 0755 "$INSTALL_DIR"
mkdir -p "$(dirname -- "$SERVICE_PATH")"
mkdir -p "$(dirname -- "$SLEEP_HOOK_PATH")"

copy_file "$SCRIPT_DIR/oxp2p-audio-fix.sh" "$INSTALL_DIR/oxp2p-audio-fix.sh" 0755
copy_file "$SCRIPT_DIR/fix_audio_sleep.sh" "$INSTALL_DIR/fix_audio_sleep.sh" 0755
copy_file "$SCRIPT_DIR/install.sh" "$INSTALL_DIR/install.sh" 0755
copy_file "$SCRIPT_DIR/uninstall.sh" "$INSTALL_DIR/uninstall.sh" 0755
copy_file "$SCRIPT_DIR/README.md" "$INSTALL_DIR/README.md" 0644

write_env_file
write_marker
write_service
write_sleep_hook

if [ "$DISABLE_HDA_POWER_SAVE" -eq 1 ]; then
    write_power_save_conf
fi

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
echo "Installed codec policy: $ENV_PATH"
echo "Installed systemd service: $SERVICE_PATH"
echo "Installed resume hook: $SLEEP_HOOK_PATH"
if [ "$DISABLE_HDA_POWER_SAVE" -eq 1 ]; then
    echo "Installed HDA power-save override: $POWER_SAVE_CONF_PATH"
fi
if [ "$START_SERVICE" -eq 0 ]; then
    echo "Service is enabled but was not started. To apply now, run: sudo systemctl start fix_audio.service"
fi
