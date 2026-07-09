# ✅ How to Fix Internal Speakers on the OneXPlayer 2 Pro (7840U/8840U)

This guide walks you through enabling internal speaker audio on the **OneXPlayer 2 Pro**. By default, internal speakers may not work out of the box, but a script resolves the issue with a little setup.

>⚠️  Note on `hda-verb` Use
>
>This fix uses `hda-verb` to send low-level audio commands. While widely used, it carries some risk of audio instability or hardware issues.  
>**Use at your own risk.**


---

## 📝 Step-by-Step Instructions

### 1. **Download the Files**

Create a directory in /home/bazzite
```bash
mkdir -p /home/bazzite/oxp2p-audio-fix
```
Download the repository files into the newly created directory.

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
cd /home/bazzite/oxp2p-audio-fix
sudo bash ./install.sh
```

The installer applies the fix at boot and installs a system-sleep hook to reapply it after resume. It does not install `alsa-tools` for you.

It installs:
- Runtime files into `/home/bazzite/oxp2p-audio-fix`
- A boot service at `/etc/systemd/system/fix_audio.service`
- A resume hook at `/etc/systemd/system-sleep/oxp2p-audio-fix`

If you install the repo somewhere else, pass the same path to the installer:

```bash
sudo bash ./install.sh --install-dir /path/to/oxp2p-audio-fix
```

To install without starting the service immediately:

```bash
sudo bash ./install.sh --no-start
```

---

## Uninstall

```bash
sudo bash /home/bazzite/oxp2p-audio-fix/uninstall.sh
```

For a custom install path:

```bash
sudo bash /path/to/oxp2p-audio-fix/uninstall.sh --install-dir /path/to/oxp2p-audio-fix
```

To remove only the systemd service and sleep hook while keeping the installed files:

```bash
sudo bash /home/bazzite/oxp2p-audio-fix/uninstall.sh --keep-files
```

## 🎉 Done!
The internal speakers should be working at this point.  
After a reboot, they should continue to work. If you reinstall the OS or reset your system, just re-follow this guide.
