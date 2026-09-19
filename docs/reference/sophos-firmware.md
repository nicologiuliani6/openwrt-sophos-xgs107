# Obtaining official Sophos SFOS firmware for the XGS 107

Why this matters: the ARM side of the switch needs a kernel, a rootfs and
Marvell's **CPSS agent**. Prior art obtained all three by extracting them
from an official Sophos firmware image (see [prior-art.md](prior-art.md)).
Until the open Marvell CPSS agent is proven to work as a substitute, the
official image is the source of the ARM payload.

**Do not download automatically.** This document records where and how; the
download is a manual step.

---

## Primary source — Sophos Firewall Installers (public)

<https://www.sophos.com/en-us/support/downloads/firewall-installers>

- **Publicly accessible.** No MySophos login required to reach the page or
  the files.
- A **serial number is required to activate and register an install** —
  but that gates *running SFOS*, not *downloading the image*. For our
  purposes (extracting the ARM payload) the download alone is enough. The
  XGS serial is embedded in the hardware anyway.
- Formats: **ISO** for hardware and software installs; ZIP for the VM
  images (VMware, Hyper-V, KVM, Citrix).
- Covers **XGS Series hardware appliances**, which includes the desktop
  models — 87 / 107 / 116 / 126 / 136.
- Versions listed at last check: **SFOS 22.0.1.490** (current) and Common
  Criteria firmware 19.0.2 (legacy).
- Page warning: *"Installing any of these on an existing device instance
  will wipe all data and settings to factory defaults."* Irrelevant if we
  only unpack the ISO, critical if it is ever booted on the appliance.

Take the **hardware ISO**, not the VM ZIP — the VM images have no reason
to carry an ARM/NPU payload.

### Which version?

Unknown which SFOS version the prior work extracted from. Reasonable
approach: start with the **current release for XGS hardware**, and check
what the appliance itself shipped with (visible on the x86 console or in
the stock SFOS UI) as a second candidate if extraction comes up empty.

---

## Alternative / archival sources

- **Internet Archive** hosts at least one older install/restore ISO
  (SFOS 18.5.1): <https://archive.org/details/sfos-18.5.1>
  Useful mainly if a specific older version turns out to be needed. Note
  18.5 predates the XGS series' current firmware line — verify it actually
  contains an XGS NPU payload before relying on it.
- **SFLoader** — Sophos's recovery loader. Documented for SG/XG.
  **Explicitly does not apply to XGS**: for XGS the intended recovery path
  is USB reimage. Recorded here so it isn't pursued by mistake.
  <https://www.avanet.com/en/kb/sophos-firewall-sfloader/>

---

## Official reimage procedure (for reference)

From Sophos docs — this is how the ISO is *meant* to be used. We are not
going to run it, but knowing it explains the image's structure.

<https://docs.sophos.com/nsg/sophos-firewall/22.0/Help/en-us/webhelp/onlinehelp/AdministratorHelp/BackupAndFirmware/Firmware/FirmwareReimageXGFirewall/index.html>

1. Download the installer for the product and platform from the Firewall
   Installers page.
2. Write it to a USB stick (balenaEtcher, or `dd`).
3. Power down the appliance, insert the stick, power on. The Sophos
   Firmware Installer starts automatically.
4. Progress is shown on the LCD / status LEDs. **XGS Series have no
   monitor port** — the RJ45 console is the way to watch it.
5. Remove the stick, confirm restart.

> Reimaging **deletes all data on the firewall**. If our unit still has a
> working stock SFOS install, that install is a reference for what a
> functioning ARM side looks like — dump what is useful from it *before*
> ever reimaging.

---

## What we actually want out of the ISO

Extraction method is an open question — prior art did not publish it.
Working plan, cheapest first:

1. `7z x` / loopback-mount the ISO; inventory it.
2. Look for a payload directory or archive aimed at the NPU/switch: names
   containing `npu`, `nps`, `marvell`, `mrvl`, `cpss`, `prestera`, `arm`,
   `aarch64`.
3. Nested images are likely — squashfs, cpio/initramfs, tarballs, or a raw
   eMMC/partition image. `binwalk` the candidates rather than guessing.
4. Targets, in order of value:
   - the **CPSS agent** binary (the irreplaceable piece),
   - the ARM **kernel** (+ device tree, if separate),
   - the ARM **rootfs**,
   - any **u-boot** image, for comparison against what is on the SPI flash.
5. Confirm architecture with `file` — expect ARM (32-bit) or AArch64. This
   also tells us which `linux-firmware` prestera image flavour is relevant
   on the x86 side.

Record findings in `logs/`, and note the exact SFOS version everything
came from.

---

## Licensing — read before publishing anything

SFOS, the ARM userland, and Marvell's CPSS agent are **proprietary**.

- Extracting them and running them on the appliance they shipped on is a
  defensible use of hardware that was legitimately acquired.
- **Redistributing them is not.** Do not commit extracted binaries to this
  repo, do not attach them to a forum post, do not put them in an OpenWrt
  image that gets published.
- `.gitignore` already excludes `firmware-refs/`; keep any extracted
  Sophos payload there or elsewhere outside version control.
- The long-term fix is replacing the extracted CPSS agent with the
  **open** one from Marvell's `switchdev-buildroot`. That is the only path
  to a redistributable OpenWrt image — see
  [openwrt-porting-plan.md](../architecture.md).
