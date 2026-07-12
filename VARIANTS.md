# Adapting the Fix to Other Hardware Variants

The verb sequence in `oxp2p-audio-fix.sh` was captured on the **OneXPlayer 2 Pro 8840U**. Other variants (such as the 7840U model, or future revisions) may use the same codec at the same PCI address — or they may not. This document describes how to find out, and how to build an ad-hoc sequence when the hardware differs.

The coefficient writes this fix performs are volatile: nothing is written to firmware or EEPROM, and a full power-off resets the codec to its defaults. The realistic worst case of a mismatched sequence is broken or muted audio until reboot. Still, never force the fix (`-f`) on a codec that has not been verified.

## Step 1: Collect diagnostics

On the device, from the repository directory:

```bash
bash collect-diagnostics.sh
sudo bash collect-diagnostics.sh --dump-coef oxp2p-diag-coef.txt
```

The first command produces `oxp2p-audio-diagnostics.txt` (read-only collection: codec identity, PCI topology, kernel HDA messages). The second additionally dumps the 256 Realtek coefficient registers of node 0x20; it requires root and `alsa-tools`, only touches the coefficient index register, and restores it afterward.

If the COEF dump reports that the target audio path was not found, look at the `/dev/snd/by-path` section of the first report and re-run with the path you see there:

```bash
sudo bash collect-diagnostics.sh --dump-coef --target /dev/snd/by-path/<device> oxp2p-diag-coef.txt
```

That situation is itself a finding: it means audio sits at a different PCI address on your variant, and the hard-coded path in `oxp2p-audio-fix.sh` would need adapting.

## Step 2: Compare the codec identity

The lines that matter, also available directly via:

```bash
grep -E '^(Codec|Vendor Id|Subsystem Id)' /proc/asound/card*/codec#0
```

Compare them against a known-working 8840U install. Three outcomes:

1. **Codec and PCI path match** (same `Vendor Id`, same `Subsystem Id`, audio at `pci-0000:64:00.6`): the existing sequence almost certainly applies. Do a supervised first run (below), then install with strict matching:

   ```bash
   sudo bash ./install.sh --codec-vendor-id <your-vendor-id> --codec-subsystem-id <your-subsystem-id>
   ```

2. **Codec matches but the PCI path differs**: the sequence is likely fine, but `AUDIO_BY_PATH` in `oxp2p-audio-fix.sh` must point at your device. Share your report in an issue so the path can be parametrized.

3. **Codec differs**: do not install. Build an ad-hoc sequence as described below.

## Supervised first run

Even when the codec identity matches, apply the fix once manually before installing anything persistent. Until `install.sh` is run, the fix only lives until the next full power-off.

```bash
sudo ./oxp2p-audio-fix.sh     # answer y at the interactive prompt
speaker-test -c2 -t wav       # or play any audio; check the active output and volume first
```

Three possible outcomes:

- **Speakers work**: take a post-fix COEF dump *before rebooting*, while the applied state is still live, then install with your exact ids:

  ```bash
  sudo bash collect-diagnostics.sh --dump-coef oxp2p-diag-coef-postfix.txt
  ```

  After installing, verify persistence: reboot (speakers should work on their own), then suspend and resume (the sleep hook reapplies the fix). If audio later disappears after the device sits idle while awake, re-run the installer with `--disable-hda-power-save` added.

  The post-fix dump also gives you **sentinel coefficients**: compare it against the cold-boot dump (`diff` the two files) and pick one or two coefficients whose post-fix value differs from the cold value and matches a direct write in the verb sequence. Pass them to the installer as `--sentinel-coef 0xIDX=0xVALUE` — the resume hook then *verifies* the fix through them and reapplies only when the check fails, instead of blindly reapplying. `oxp2p-audio-fix.sh -c` reports the current state (exit 0: applied, 6: not applied, 7: no sentinels configured).

- **No sound, nothing else strange**: the sequence does not apply to your variant as-is; continue with Step 3 below.

- **Distorted or broken audio**: power the device off completely (a full shutdown, not a reboot). The codec resets to its defaults and nothing persists.

## Step 3 (codec differs): capture the working configuration from Windows

This requires a dual-boot setup where the internal speakers work under Windows. The idea: the Realtek Windows driver programs the codec's coefficient registers at startup, and a **warm reboot usually preserves codec register state** — so the Windows-configured values can be read back from Linux and compared against the broken cold-boot state.

1. **Cold boot** into Linux (full power-off first, not a restart). Do not start the fix service. Dump the broken baseline:

   ```bash
   sudo bash collect-diagnostics.sh --dump-coef oxp2p-diag-coef-cold.txt
   ```

2. Boot into **Windows** and confirm the speakers actually produce sound.

3. **Restart** from Windows straight into Linux — restart, not shutdown, so the codec is not power-cycled. Dump again as soon as possible after boot:

   ```bash
   sudo bash collect-diagnostics.sh --dump-coef oxp2p-diag-coef-warm.txt
   ```

4. Diff the two dumps:

   ```bash
   diff oxp2p-diag-coef-cold.txt oxp2p-diag-coef-warm.txt
   ```

The coefficients that changed between the two dumps are the candidates for what the Windows driver configures on your variant. From that diff, a verb sequence (`SET_COEF_INDEX` + `SET_PROC_COEF` pairs) can be derived and tested.

Caveats to keep in mind:

- Warm-reboot persistence is firmware-dependent; if the two dumps are identical everywhere, the BIOS may be resetting the codec on reboot and this method will not work on your device.
- The Linux HDA driver runs its own init at boot and may rewrite some coefficients before the warm dump is taken, so the diff is a strong starting point, not a guaranteed 1:1 capture of the Windows driver's writes.
- Some Realtek coefficient state lives in banked/indirect registers that a linear 0x00–0xff dump does not reach. If the diff looks too small to explain working speakers, that is the likely reason.

## What to share

When reporting a variant, include:

- `oxp2p-audio-diagnostics.txt` (always)
- `oxp2p-diag-coef.txt` (if `--dump-coef` worked)
- The cold/warm pair from Step 3, if you went through the Windows capture

The report contains no secrets by design: codec identity, PCI layout and register values. Skim it anyway before posting publicly if that matters to you. Collected reference reports live under `reports/<variant>/` in this repository.

## Known variants

### 7840U — ARP23P (BIOS 1.05, 07/31/2023)

- Codec: Realtek ALC245, Vendor Id `0x10ec0245`, Subsystem Id `0x1f751602`, Revision Id `0x100001`
- Audio controller: `0000:64:00.6` (AMD Ryzen HD Audio, `1022:15e3`) — matches the default target path
- Node 0x20 present with 142 coefficients; all codec guardrails pass
- Reference reports: `reports/7840u-arp23p/` (cold-boot baseline and post-fix COEF dump)
- Sentinel coefficients (values only present when the fix is applied): `0x10=0x0220`, `0x67=0x3000`
- **Status: verified working (2026-07-10).** The existing verb sequence applies as-is; internal speakers confirmed working after a supervised first run. The strict install line:

  ```bash
  sudo bash ./install.sh --codec-vendor-id 0x10ec0245 --codec-subsystem-id 0x1f751602 \
      --sentinel-coef 0x10=0x0220 --sentinel-coef 0x67=0x3000
  ```

Net effect of the sequence visible in the linear COEF dump (cold → post-fix): `0x10: 0x0020 → 0x0220`, `0x2a: 0x004a → 0x0000`, `0x2b: 0x5294 → 0xffff`, `0x4a: 0x20b0 → 0xa0a0`, `0x67: 0x1000 → 0x3000`. The `0x10` and `0x67` values match direct writes in the sequence; the rest reflect the sequence plus normal driver activity. Most of the sequence's writes target banked registers that a linear dump does not reach, so a small diff here is expected.

### 8840U

The variant the verb sequence was captured on (see the credit links in the README). No reference diagnostics have been collected for it yet — contributions welcome.
