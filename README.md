# ✅ How to Fix Internal Speakers on the OneXPlayer 2 Pro (7840U/8840U)

This guide walks you through enabling internal speaker audio on the **OneXPlayer 2 Pro**. By default, internal speakers may not work out of the box, but a script resolves the issue with a little setup.

>⚠️  Note on `hda-verb` Use
>
>This fix uses `hda-verb` to send low-level audio commands. While widely used, it carries some risk of audio instability or hardware issues.  
>**Use at your own risk.**

ℹ️  The verb sequence was captured on the **8840U** variant. The **7840U** (ARP23P) variant has been verified working with the same sequence — see [VARIANTS.md](VARIANTS.md) for its codec ids and install line. For any other variant, check that your codec matches before installing:

```bash
grep -E '^(Codec|Vendor Id|Subsystem Id)' /proc/asound/card*/codec#0
```

and pass the exact ids to the installer with `--codec-vendor-id`/`--codec-subsystem-id` as shown below.

To help adapt the fix to other variants, run `bash collect-diagnostics.sh` on the device and share the resulting `oxp2p-audio-diagnostics.txt`. Add `--dump-coef` as root only if coefficient data is needed; it is limited to the target audio path and restores the saved COEF index afterward. If audio sits at a different PCI path on your variant, pass `--target PATH` with a device from `/dev/snd/by-path/`. The full procedure — codec comparison, decision tree, and capturing a working configuration from a Windows dual-boot — is documented in [VARIANTS.md](VARIANTS.md).

---

## 📝 Step-by-Step Instructions

### 1. **Download the Files**

Download or clone the repository into any temporary working directory.

```bash
git clone https://github.com/savemosca/onexplayer2pro-audio-fix.git
cd onexplayer2pro-audio-fix
```

The installer copies the runtime files into a root-owned system directory. Do not run the service directly from a user-writable directory such as `/home/bazzite`.

>All credit for this script goes to fortime2024 from the [One-netbook official Discord](https://discord.com/channels/547366894995243029/1210923924439699516/1399685604932849726) and [here](https://github.com/ChimeraOS/chimeraos/issues/742#issuecomment-2250951477)

---

### 2. **Install ALSA Tools**

```bash
sudo rpm-ostree install alsa-tools
```
A reboot will be recommended after the install is complete. Reboot before starting the service so `hda-verb` is available.

---

### 3. **Run the Installer**

```bash
sudo bash ./install.sh
```

The installer enables the fix at boot and installs a system-sleep hook to reapply it after resume. It does not start the service immediately unless you ask it to, and it does not install `alsa-tools` for you.

It installs:
- Runtime files into `/usr/local/lib/oxp2p-audio-fix`
- Codec safety policy at `/usr/local/lib/oxp2p-audio-fix/oxp2p-audio-fix.env`
- A boot service at `/etc/systemd/system/fix_audio.service`
- A resume hook at `/etc/systemd/system-sleep/oxp2p-audio-fix`
- Optionally, an HDA power-save override at `/etc/modprobe.d/oxp2p-audio-fix-power-save.conf` (with `--disable-hda-power-save`)

To apply the fix immediately after installing:

```bash
sudo systemctl start fix_audio.service
```

Or install and start in one step:

```bash
sudo bash ./install.sh --start-now
```

The script checks the expected PCI audio path, confirms the codec metadata from `/proc/asound/cardN/codec#0`, requires a Realtek vendor id prefix by default, and requires node `0x20` before writing verbs. For stricter matching, pass the exact codec IDs from your device during install:

```bash
sudo bash ./install.sh --codec-vendor-id <vendor-id> --codec-subsystem-id <subsystem-id>
```

If you install somewhere custom, use a root-owned system path:

```bash
sudo bash ./install.sh --install-dir /usr/local/lib/oxp2p-audio-fix
```

---

## Troubleshooting

### Speakers stop working after the device sits idle

The audio driver can power the codec down after a period of silence (the `snd_hda_intel` `power_save` option, enabled by default on many distributions). When the codec powers back up, the driver re-initializes it and the low-level writes applied by this fix can be lost until the next boot or resume. If that happens, reinstall with:

```bash
sudo bash ./install.sh --disable-hda-power-save
```

This writes `/etc/modprobe.d/oxp2p-audio-fix-power-save.conf` to keep the codec powered (at a small battery cost) and applies the setting immediately when possible. The uninstaller removes the override.

### Audio is crackly or stutters after resume

Some systems bring the HDA codec back before the audio stack has fully settled. The resume hook waits briefly, reapplies the fix, then applies it once more after a short delay. Reinstall the latest hook with **your own** strict codec ids (see [VARIANTS.md](VARIANTS.md) for the ids of known variants):

```bash
sudo bash ./install.sh --codec-vendor-id <your-vendor-id> --codec-subsystem-id <your-subsystem-id>
```

If the issue still happens, try keeping the HDA codec powered while awake:

```bash
sudo bash ./install.sh --codec-vendor-id <your-vendor-id> --codec-subsystem-id <your-subsystem-id> --disable-hda-power-save
```

The resume timings are stored in `/usr/local/lib/oxp2p-audio-fix/oxp2p-audio-fix.env` and can be tuned with `RESUME_WAIT_SECONDS`, `RESUME_SETTLE_SECONDS`, `RESUME_REAPPLY_COUNT`, and `RESUME_REAPPLY_INTERVAL_SECONDS`. Re-running the installer preserves previously tuned timings.

---

## Uninstall

```bash
sudo bash /usr/local/lib/oxp2p-audio-fix/uninstall.sh
```

For a custom install path:

```bash
sudo bash /path/to/installed/oxp2p-audio-fix/uninstall.sh --install-dir /path/to/installed/oxp2p-audio-fix
```

To remove only the systemd service and sleep hook while keeping the installed files:

```bash
sudo bash /usr/local/lib/oxp2p-audio-fix/uninstall.sh --keep-files
```

## 🎉 Done!
The internal speakers should be working at this point.  
After a reboot, they should continue to work. If you reinstall the OS or reset your system, just re-follow this guide.
