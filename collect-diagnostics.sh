#!/bin/bash
set -euo pipefail

# Collect audio diagnostics from a OneXPlayer 2 Pro to help adapt the
# audio fix to hardware variants (e.g. 7840U vs 8840U).
#
# The default run is read-only. With --dump-coef it also reads the
# Realtek vendor coefficient registers (node 0x20) through hda-verb,
# which requires root and alsa-tools; reading coefficients only selects
# an index register and is harmless.

OUTPUT_FILE="oxp2p-audio-diagnostics.txt"
DUMP_COEF=0

usage() {
    echo "Usage: $0 [--dump-coef] [OUTPUT_FILE]" >&2
    echo "  --dump-coef   Also dump Realtek COEF registers (requires root and hda-verb)" >&2
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

dump_coefs() {
    local codec card device codec_name idx hex value

    for codec in /proc/asound/card*/codec#0; do
        [ -r "$codec" ] || continue
        grep -q '^Codec: .*Realtek' "$codec" || continue

        card=${codec#/proc/asound/card}
        card=${card%%/*}
        device="/dev/snd/hwC${card}D0"
        if [ ! -e "$device" ]; then
            echo "Skipping $codec: $device does not exist"
            continue
        fi

        codec_name=$(awk -F': ' '/^Codec:/{print $2; exit}' "$codec")
        printf -- '--- COEF dump for %s (%s) ---\n' "$device" "$codec_name"

        for idx in $(seq 0 255); do
            hex=$(printf '0x%02x' "$idx")
            if ! LC_ALL=C hda-verb "$device" 0x20 0x500 "$hex" >/dev/null 2>&1; then
                echo "Failed to set COEF index $hex; stopping dump for $device"
                break
            fi
            value=$(LC_ALL=C hda-verb "$device" 0x20 0xc00 0x0 2>/dev/null | awk '/value =/{print $NF; exit}')
            printf 'coef %s = %s\n' "$hex" "${value:-unknown}"
        done
    done
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
