#!/bin/bash
set -euo pipefail

# Collect audio diagnostics from a OneXPlayer 2 Pro to help adapt the
# audio fix to hardware variants (e.g. 7840U vs 8840U).
#
# The default run is read-only. With --dump-coef it also reads the target
# Realtek vendor coefficient registers (node 0x20) through hda-verb. That
# requires root and alsa-tools; the dump changes only the COEF index register
# and restores the original index afterward.

OUTPUT_FILE="oxp2p-audio-diagnostics.txt"
DUMP_COEF=0
TARGET_AUDIO_BY_PATH="${TARGET_AUDIO_BY_PATH:-/dev/snd/by-path/pci-0000:64:00.6}"

usage() {
    echo "Usage: $0 [--dump-coef] [OUTPUT_FILE]" >&2
    echo "  --dump-coef   Dump target Realtek COEF registers (requires root and hda-verb)" >&2
    echo "  OUTPUT_FILE   Where to write the report (default: $OUTPUT_FILE)" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
      --dump-coef)
        DUMP_COEF=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        usage
        exit 64
        ;;
      *)
        OUTPUT_FILE=$1
        shift
        ;;
    esac
done

if [ "$DUMP_COEF" -eq 1 ]; then
    if [ "$(id -u)" -ne 0 ]; then
        echo "--dump-coef requires root. Try: sudo $0 --dump-coef" >&2
        exit 1
    fi
    if ! command -v hda-verb >/dev/null; then
        echo "--dump-coef requires hda-verb. Install alsa-tools first." >&2
        exit 2
    fi
fi

section() {
    printf '\n===== %s =====\n' "$1"
}

read_hda_value() {
    local device=$1
    local nid=$2
    local verb=$3
    local param=$4
    local output value

    if ! output=$(LC_ALL=C hda-verb "$device" "$nid" "$verb" "$param" 2>&1); then
        printf '%s\n' "$output" >&2
        return 1
    fi

    case "$output" in
      *ioctl*|*invalid*|*Invalid*|*open:*)
        printf '%s\n' "$output" >&2
        return 1
        ;;
    esac

    value=$(printf '%s\n' "$output" | awk '/value =/{print $NF; exit}')
    [ -n "$value" ] || return 1
    printf '%s\n' "$value"
}

set_coef_index() {
    local device=$1
    local index=$2
    local output

    if ! output=$(LC_ALL=C hda-verb "$device" 0x20 0x500 "$index" 2>&1); then
        printf '%s\n' "$output" >&2
        return 1
    fi

    case "$output" in
      *ioctl*|*invalid*|*Invalid*|*open:*)
        printf '%s\n' "$output" >&2
        return 1
        ;;
    esac
}

resolve_target_card() {
    local control_device card

    if [ ! -e "$TARGET_AUDIO_BY_PATH" ]; then
        echo "Target audio path was not found: $TARGET_AUDIO_BY_PATH" >&2
        return 1
    fi

    control_device=$(realpath "$TARGET_AUDIO_BY_PATH") || {
        echo "Unable to resolve target audio path: $TARGET_AUDIO_BY_PATH" >&2
        return 1
    }

    case "$control_device" in
      /dev/snd/controlC*)
        card=${control_device#/dev/snd/controlC}
        ;;
      *)
        echo "Unexpected target control device: $control_device" >&2
        return 1
        ;;
    esac

    case "$card" in
      ''|*[!0-9]*)
        echo "Unable to determine ALSA card number from: $control_device" >&2
        return 1
        ;;
    esac

    printf '%s\n' "$card"
}

dump_coefs() {
    local card codec device codec_name idx hex value saved_index

    if ! card=$(resolve_target_card); then
        echo "Skipping COEF dump because the target audio card could not be resolved."
        return 0
    fi

    codec="/proc/asound/card${card}/codec#0"
    device="/dev/snd/hwC${card}D0"

    if [ ! -r "$codec" ]; then
        echo "Skipping COEF dump: codec metadata is not readable: $codec"
        return 0
    fi
    if ! grep -q '^Codec: .*Realtek' "$codec"; then
        echo "Skipping COEF dump: target codec is not Realtek: $codec"
        return 0
    fi
    if ! grep -q '^Node 0x20 ' "$codec"; then
        echo "Skipping COEF dump: target codec does not expose node 0x20: $codec"
        return 0
    fi
    if [ ! -e "$device" ]; then
        echo "Skipping COEF dump: HDA hwdep device does not exist: $device"
        return 0
    fi

    codec_name=$(awk -F': ' '/^Codec:/{print $2; exit}' "$codec")
    printf -- '--- COEF dump for %s (%s) via %s ---\n' "$device" "$codec_name" "$TARGET_AUDIO_BY_PATH"

    if ! saved_index=$(read_hda_value "$device" 0x20 0xd00 0x0); then
        echo "Skipping COEF dump: unable to read current COEF index for safe restore."
        return 0
    fi
    printf 'saved coef index = %s\n' "$saved_index"

    for idx in $(seq 0 255); do
        hex=$(printf '0x%02x' "$idx")
        if ! set_coef_index "$device" "$hex"; then
            echo "Failed to set COEF index $hex; stopping dump for $device"
            break
        fi
        if value=$(read_hda_value "$device" 0x20 0xc00 0x0); then
            printf 'coef %s = %s\n' "$hex" "$value"
        else
            printf 'coef %s = unknown\n' "$hex"
        fi
    done

    if set_coef_index "$device" "$saved_index"; then
        printf 'restored coef index = %s\n' "$saved_index"
    else
        printf 'WARNING: failed to restore saved coef index = %s\n' "$saved_index"
    fi
}

{
    section "Collected"
    date -u '+%Y-%m-%dT%H:%M:%SZ'

    section "System"
    uname -a
    for dmi_field in product_name product_version board_name board_vendor bios_version bios_date; do
        if [ -r "/sys/class/dmi/id/$dmi_field" ]; then
            printf '%s: %s\n' "$dmi_field" "$(cat "/sys/class/dmi/id/$dmi_field")"
        fi
    done

    section "PCI audio devices"
    lspci -nn 2>/dev/null | grep -iE 'audio|multimedia' || echo "lspci not available or no audio devices found"

    section "/dev/snd/by-path"
    ls -l /dev/snd/by-path/ 2>/dev/null || echo "No /dev/snd/by-path directory"

    section "Target audio path"
    printf 'TARGET_AUDIO_BY_PATH=%s\n' "$TARGET_AUDIO_BY_PATH"
    realpath "$TARGET_AUDIO_BY_PATH" 2>/dev/null || echo "Target audio path is not present"

    section "ALSA cards"
    cat /proc/asound/cards 2>/dev/null || echo "No /proc/asound/cards"

    section "Codec dumps"
    found_codec=0
    for codec in /proc/asound/card*/codec#*; do
        [ -r "$codec" ] || continue
        found_codec=1
        printf -- '--- %s ---\n' "$codec"
        cat "$codec"
    done
    if [ "$found_codec" -eq 0 ]; then
        echo "No readable codec dumps under /proc/asound"
    fi

    section "Kernel HDA messages"
    dmesg 2>/dev/null | grep -iE 'hda|alc[0-9]' || echo "dmesg not readable (run as root for kernel messages)"

    if [ "$DUMP_COEF" -eq 1 ]; then
        section "Realtek COEF registers (node 0x20)"
        dump_coefs
    fi
} > "$OUTPUT_FILE"

echo "Diagnostics written to: $OUTPUT_FILE"
if [ "$DUMP_COEF" -eq 0 ]; then
    echo "Re-run with --dump-coef (as root, with alsa-tools installed) to include the Realtek COEF registers."
fi
