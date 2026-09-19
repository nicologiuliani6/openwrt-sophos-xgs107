# OpenWrt on the XGS 107w x86 side

Result (2026-09-19): the x86 boots **OpenWrt** (x86/64, kernel 6.18.52) from
its internal 64 GB SATA flash, through the GRUB that SFOS left there. The
Wi-Fi card is recognised (`ath10k`, QCA988x hw2.0, dual band). SFOS is not
needed and no longer boots usefully. The NPU (switch) side runs its own
OpenWrt, see [openwrt-install.md](openwrt-install.md); the two are
independent.

## What the box looks like from the x86

| Item | Value |
|---|---|
| CPU / RAM | AMD RX-216TD (Family 15h), 4 GB |
| Boot | UEFI (AMI, BIOS 2A06) → GRUB 2.02 (EFI) on the disk's `/boot` |
| Disk | 64 GB SATA flash, MBR with only 2 real partitions |
| Console | RJ45 or micro-USB (PL2303), **38400 8N1**; GRUB and the kernel both use it |
| Wi-Fi | `02:00.0 [168c:003c]`, `ath10k` with the CT firmware, 2.4 + 5 GHz (VHT80) |
| USB | xHCI + EHCI; RTL8152 / AX88179 / CDC USB Ethernet drivers are in the image |
| **Network** | `ntb0`, a virtual Ethernet to the NPU over PCIe ([x86-npu-link.md](x86-npu-link.md)); 192.168.1.2 |

## Layout on disk

- **`sda1`** (MBR entry 1, 136 MB ext4): SFOS `/boot`. Holds `grub/grub.cfg`,
  the SFOS kernels and now `/openwrt/vmlinuz` (the OpenWrt kernel).
- **`sda2`** (MBR entry 2, 64 MB): untouched.
- **`sda3`** (MBR entry **3, added by us**, LBA 19623384, 7955400 sectors,
  3.79 GB): the OpenWrt ext4 root. This is the area SFOS used as swap
  (`/dev/swap`, "sda8" in SFOS's own numbering).
- Everything else (SFOS's data) is untouched.

GRUB entries: `SFLoader`, `19_5_3_652`, `19_5_4_718` (SFOS, unchanged) and
`OpenWrt` (default, entry 3):

```
linux /openwrt/vmlinuz root=/dev/sda3 rootwait rootfstype=ext4 console=tty0 console=ttyS0,38400n8 noinitrd libata.force=noncq …
```

The OpenWrt kernel has AHCI, SCSI disk and ext4 built in, so no initrd.

### Why the MBR needed an extra entry

SFOS does not describe most of its partitions in the MBR. It creates
`sda3`…`sda9` at run time with its own numbering (its `/dev/boot` is the
MBR's first entry, its `/dev/swap` is "sda8"). A normal kernel therefore
sees only `sda1` and `sda2`, and `root=/dev/sda8` panics with
`Cannot open root device`. Entry 3 makes the swap area visible. Sector 0
was backed up first: `/boot/mbr-sda.bak` (on `sda1`). The original entries
are `0x83 19213784+278528` and `0x83 19492312+131072`, entries 3 and 4 empty.

## How it was installed

From the SFOS advanced shell, in one session, by `scripts/95-x86-install.sh`
(which also runs `scripts/96-x86-mbr.py`), with the stock NPU firmware
running so that the x86 has a network to fetch from the PC. Steps:
1. `swapoff /dev/swap`, write the ext4 rootfs image (512 MB) to `/dev/swap`,
   verify by reading **the whole disk node** `/dev/sda` at the partition's
   LBA after dropping caches;
2. add the MBR entry (`96-x86-mbr.py`; checks that entries 3 and 4 are
   empty, entries 1 and 2 match SFOS's `sda6`/`sda7`, and that an ext4
   superblock is really at the target);
3. copy the kernel to `/boot/openwrt/`, add the GRUB entry, default = 3;
4. put the NPU's OpenWrt kernel back (see openwrt-install.md).

**Never boot SFOS after this.** At every boot SFOS runs `mkswap` on that
partition, which destroys the OpenWrt root. The SFOS GRUB entries are still
there but are a dead end; with the NPU on OpenWrt they hang at `Loading
network interface drivers…` anyway.

## Getting a shell on the x86 when the box has no display and no network

This was the hard part of the job; the tools are in `scripts/`:

- **micro-USB console** (`/dev/ttyUSB*`, PL2303, 38400): the x86's serial
  console. It disappears and comes back **under a new `ttyUSBn`** at every
  power cycle: use `/dev/serial/by-id/usb-Prolific*-port0`.
- `90-x86-grub.py`: catches GRUB on that console (5 s window) and drives
  it. It rebuilds GRUB's screen from its ANSI output with a tiny terminal
  emulator, because GRUB at 38400 baud redraws the whole screen on every
  key, **drops characters** and echoes each one twice. What works
  reliably is **GRUB's command line** (`c`): it types the `linux` line one
  character at a time, checks it on screen, then `boot`. The `e` editor is
  not usable this way.
- `91-console-log.py`: logs the console across the port renumbering.
- To boot SFOS **without** the NPU (so it does not hang waiting for it) the
  kernel takes `module_blacklist=mv_armada_drv,mv_giu_drv,mv_pcinet_drv,
  mv_pport,mv_nwa_host,mv_mux_lag,mv_nwa_host_mux_lag,mgmt_net,
  mgmt_net_mux_lag,usfp_firewall`. SFOS then reaches its login, but has no
  network (the x86 has no NIC of its own).
- `init=` and `rdinit=` on SFOS's kernel do nothing: its initramfs runs its
  own init regardless. That was tried and is a dead end.
- SFOS's SysRq works from the shell (`echo b > /proc/sysrq-trigger`), but a
  serial BREAK does not trigger it.

## Mistakes worth remembering

1. **`dd of=/dev/sda8` writes to RAM on SFOS.** SFOS has no `/dev/sda8`; its
   nodes are `/dev/boot`, `/dev/swap`, `/dev/var`. `dd of=` on a missing
   path silently creates a regular file in `/dev` (tmpfs). The "verified"
   image was that file, the disk was never written, and the first OpenWrt
   boot correctly found nothing. The script now requires `[ -b /dev/swap ]`
   and verifies against the raw disk.
2. A sanity check that passes for the wrong reason is worse than none: read
   back through a *different* path than the one you wrote.
3. Tools that call `pkill -f <pattern>` kill their own shell when the
   pattern is in the command line.

## Wi-Fi

`wifi config` generated `/etc/config/wireless`: `radio0`, 5 GHz, channel 36,
VHT80, and an AP `default_radio0` on the `lan` network that is **disabled**
and has **no encryption** on purpose. To use it, set a WPA2/WPA3 key first
(`uci set wireless.default_radio0.encryption=sae-mixed`,
`…key=<password>`, `…ssid=<name>`, `…disabled=0`, `wifi reload`). Without a
USB Ethernet dongle to the switch, clients of that AP reach only the x86.

## Network (since 2026-09-19)

The x86 no longer needs a dongle: it reaches the switch through the PCIe
link to the NPU, see [x86-npu-link.md](x86-npu-link.md). `ntb0` is bridged in
`br-lan`, address 192.168.1.2, gateway/DNS 192.168.1.1, its own DHCP server off.
The NPU's LuCI has a menu entry *Network → Wi-Fi / x86 module* that links
to the x86's wireless page. The Wi-Fi radio (`radio0`, QCA988x, 5 GHz ch 36
VHT80, country IT) is up; the AP is defined but **disabled and open**: set
SSID, WPA key and enable it in LuCI (it was tested once with WPA2:
`AP-ENABLED`).

## Not done / open

- The root filesystem is 3.79 GB partition with a 620 MB ext4: online
  `resize2fs` stops at "add group #5" (the image has no reserved GDT
  blocks). 570 MB are free; growing needs an offline resize or a bigger image.
- No root password.
- Recovery to SFOS on the x86 would need a USB stick with the Sophos
  installer (public download, see [sophos-firmware.md](sophos-firmware.md)).
