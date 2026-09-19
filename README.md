# Sophos XGS 107w — CN9130 / 88E6193X bring-up (Linux, OpenWrt)

Reviving a Sophos XGS 107w desktop firewall appliance whose 8 switch ports
are unusable without Sophos's proprietary SFOS. Goal: get the switch
ports functional under Linux/OpenWrt without Sophos's proprietary SFOS.

Hardware received as a gift from a community contact — the same person who
diagnosed this exact problem on the OpenWrt forum in 2023.

No usernames, handles, or real names appear anywhere in this repo. Sources
are cited as links or as the community they came from.

## Stato aggiornato

**This supersedes the plan below.** Updated 2026-09-18 after reading the
running unit from inside SFOS. Full detail:
[docs/hardware-architecture.md](docs/hardware-architecture.md).

### What `[11ab:7080]` actually is

The split-brain picture holds, but the components are different from what
was assumed. It is **not a Prestera switch**:

- **NPU = Marvell CN9130** SoC (4× Cortex-A72, ~1.5 GB RAM, 7.3 GB eMMC,
  4 MB SPI u-boot) attached to the x86 as a **PCIe endpoint**. It runs its
  own Linux 4.14 (Marvell SDK) from eMMC.
- **Switch = Marvell 88E6193X** on the CN9130's MDIO bus. Ports 1-8 are
  its internal PHYs, the SFP "F1" is its port 9, and its port 0 is a 10G
  link to the CN9130's `mvpp2` Ethernet.
- The x86 reaches the ports only through Sophos-proprietary host drivers
  (`mv_armada_drv`, `mv_giu_drv`, `mv_pcinet_drv`, …, kernel 4.14.277
  only). That is why stock Debian, OPNsense and OpenWrt on the x86 see no
  ports.
- The NPU console is **x86 `/dev/ttyS2` @ 115200**. SFOS has a root shell
  on the NPU via `xgs-ssh.sh`.

### Direction

Target: **mainline Linux, then OpenWrt, running on the CN9130 itself**.
- The CN9130, `mvpp2`, `sdhci-xenon` and the `mv88e6xxx` DSA driver
  (88E6193X) are all in mainline.
- L2 switching stays in hardware, and routing runs on 4 A72 cores behind a
  10G uplink.
- No proprietary blobs, so the image is redistributable.

The x86 (and its Wi-Fi) is a later, optional phase.

**Status 2026-09-19:**
- mainline Linux and **OpenWrt run on the CN9130** (booted from RAM with
  kexec), with all 8 ports + SFP via DSA;
- WAN DHCP works and gigabit line rate is measured (941 Mbit/s);
- **OpenWrt is installed on the NPU eMMC** (slot p1) and boots from the stock
  U-Boot (2026-09-19). Stock Sophos stays as the U-Boot fallback.
- Verified after a power cycle: LAN 192.168.1.1 (panel port 1, 3-8, SFP),
  WAN DHCP on panel port 2, NAT routing, 941 Mbit/s line rate, 2 GB RAM.
- **The x86 runs OpenWrt too** (2026-09-19), from its internal disk via the
  existing GRUB; Wi-Fi card detected (ath10k). SFOS is not needed any more.
  See [docs/x86-openwrt.md](docs/x86-openwrt.md). The x86 has no network of
  its own (needs a USB Ethernet dongle to a switch port for an uplink).
- Linux upstream patches (3 DT + 1 driver) are prepared but **not sent**:
  [upstream/README.md](upstream/README.md).

Details: [docs/bench-log.md](docs/bench-log.md) §11-16,
[openwrt/](openwrt/), [docs/openwrt-install.md](docs/openwrt-install.md).

Order of work (plan approved 2026-09-18):

0. Document everything — done: [docs/bench-log.md](docs/bench-log.md),
   [docs/hardware-architecture.md](docs/hardware-architecture.md).
1. Full verified backup of NPU SPI + eMMC and of the SFOS NPU tooling,
   before any write.
2. Mainline Linux on the CN9130, booted manually from a spare eMMC slot,
   with stock left intact on p3.
3. OpenWrt (`mvebu/cortexa72`) — [docs/openwrt-porting-plan.md](docs/openwrt-porting-plan.md).

### Obsolete work

`driver/`, `patches/0001-prestera-add-dev-id-7080.patch`, `firmware-refs/`
and `scripts/05-`, `10-`, `20-` target the mainline `prestera` driver, which
does not apply to this hardware. They are kept for the record only. The
same goes for the CPSS assumptions in
[docs/prior-art.md](docs/prior-art.md), whose method (boot the ARM side)
still holds.

### Other docs

- [docs/prior-art.md](docs/prior-art.md) — community r/opnsense work.
- [docs/npu-com-serial-checklist.md](docs/npu-com-serial-checklist.md) —
  on-board header; superseded by x86 `ttyS2`.
- [docs/sophos-firmware.md](docs/sophos-firmware.md) — official SFOS
  images, for restoring stock.

## Hardware facts (confirmed)

- **Platform**: x86 AMD Embedded R-Series RX-216TD, 4 GB RAM
- **NPU**: Marvell CN9130 as PCIe endpoint, PCI ID `[11ab:7080]` (+ two
  `[11ab:7081]` functions)
- **Switch chip**: Marvell 88E6193X behind the CN9130
- **Mainboard**: silkscreen `XGS 87(W) 107(W) 1.40` — one PCB shared by
  XGS 87 and 107, board rev 1.40 (observed on our unit, 2026-09-18)
- **Ports**: 8x GbE copper (1/LAN, 2/WAN, 3/DMZ, 4, 5, 6, 7, 8) + 1x SFP
  (labeled "F1")
- **Wi-Fi**: integrated ("w" model), 2x SMA antenna connectors. Module is
  an M.2/mini-PCIe card under a black heatsink, U.FL connectors `CH0`/`CH1`
  wired, `CH2` unused — chipset not yet identified (read via `lspci`), may work out of the box independent of the switch
  problem
- **USB**: USB 3.0 port, standard xHCI, should work with any Linux out of
  the box
- **Power**: dual redundant DC IN (DC IN 1 / DC IN 2)
- **Console**: RJ45, Cisco-style rollover pinout, **38400 baud, 8N1**
  (confirmed directly by the
  contact who supplied the unit)
- **Micro-USB console**: second x86 console via on-board Prolific PL2303
  (`067b:23a3`, `/dev/ttyUSB0`), 38400 8N1. Takes priority over the RJ45
  console when both are connected. x86 only, not the switch side.
- **Installed firmware**: SFOS 19.5.4 MR-4 (Build 718); boot runs
  "Checking for NPU uboot mismatch" — SFOS manages the switch-side u-boot
- **Rack mount**: not included; third-party kits exist (Rackmount.IT
  RM-SR-T11, ~1.3U) if ever needed — not required for bring-up work

## The core problem (original framing — partly wrong, see "Stato aggiornato")

> **Correction.** This section assumed the host loads firmware into the
> ASIC over PCIe and that this is sufficient. It is not: the ARM side is a
> full independent computer that boots its own Linux from its own eMMC and
> runs the CPSS agent. Host-side firmware loading does not substitute for
> that. The Prestera protocol detail below remains accurate and useful for
> the later phase.

The Marvell chip at `[11ab:7080]` is a **Prestera-family switch ASIC**,
not a simple NIC. It has its own embedded ARM core and requires the host
to explicitly load firmware and speak a command/event-queue protocol to
it over PCIe — the switch does nothing on its own without that.

This is NOT the same problem as the Cavium SNIC10E project (no need to
reverse-engineer an undocumented protocol from scratch). Key difference:

- Mainline Linux already has an open source driver:
  `drivers/net/ethernet/marvell/prestera/` (Dual BSD/GPL)
- Firmware is **publicly distributed**, no NDA:
  `mrvl/prestera/mvsw_prestera_fw-v4.1.img` (and older versions), shipped
  in the standard `linux-firmware` package
- Protocol is fully documented in the driver source: loader ring buffer
  (magic `0xf00dfeed`), FW ready magic `0xcafebabe`, command/event queues
  with named registers — see `prestera_pci.c` in mainline Linux

**BUT**: our device ID `0x7080` is **not** in the mainline driver's
supported ID table. Currently supported IDs:

```
0xC804  PRESTERA_DEV_ID_AC3X_98DX_55
0xC80C  PRESTERA_DEV_ID_AC3X_98DX_65
0xCC1E  PRESTERA_DEV_ID_ALDRIN2
0x981F  PRESTERA_DEV_ID_98DX7312M
0x9820  PRESTERA_DEV_ID_98DX3500
0x9826  PRESTERA_DEV_ID_98DX3501
0x9821  PRESTERA_DEV_ID_98DX3510
0x9822  PRESTERA_DEV_ID_98DX3520
```

So the task is not "write a driver from scratch" — it's "figure out
whether `0x7080` speaks the same wire protocol as a sibling chip in this
list, and if so, get it recognized and talking to the public firmware."

## What happened in 2023 (prior art)

An OpenWrt forum thread from a user who tried this exact model got nothing
(no network interfaces at all — worse than a dumb switch fallback). Another
participant explained why: no driver existed publicly at the time for this
switch family with the level of detail needed, and the switch "operates as
a router unto itself (it has its own ARM processor)" — which turned out to
be the whole story, see "Stato aggiornato" above. Netgate had written a
similar driver but kept it proprietary inside pfSense Plus.

Since 2023, the mainline `prestera` driver + public firmware situation
described above has matured significantly — this may no longer be a dead
end. That's the bet this project is making.

Source: https://forum.openwrt.org/t/sophos-xgs107-and-no-network-interfaces-unknown-network-controller/168989

## Original bring-up plan (superseded — kept for the host-side steps)

1. **Console access**: USB-A → RJ45 (CH340-based) cable, 38400 baud 8N1,
   confirm you're seeing the x86 BIOS/UEFI console.
2. **Boot a live Linux** (Debian/Ubuntu USB stick) and run:
   ```
   lspci -knn
   ```
   Confirm the exact `[11ab:7080]` device is present and check what (if
   anything) the kernel already tries to bind to it.
3. **Check Wi-Fi and USB independently** — these should work regardless
   of the switch problem, worth confirming early as a "something works"
   sanity check.
4. **Patch-test the mainline `prestera` driver**: add `0x7080` to
   `prestera_pci_devices[]` in `prestera_pci.c`, rebuild the module, load
   it with the public firmware already in `linux-firmware`, and watch
   `dmesg` for the loader/FW ready magic numbers. If the loader responds
   at all, the wire protocol matches and this becomes a much shorter
   project than Cavium was.
5. If it doesn't respond: dump `lspci -vvv` BAR sizes/capabilities and
   start black-box probing BAR2 (per `prestera_pci.c`, that's where the
   FW loader + PP registers live on most variants) — this is where the
   Cavium-style methodology (systematic probing, cross-referencing
   register behavior) becomes relevant again.

## Obsolete: Prestera driver staging (kept for the record)

> Staged before the hardware was identified. `[11ab:7080]` turned out to be
> a CN9130 in PCIe endpoint mode, not a Prestera, so the `prestera` driver
> cannot bind to it meaningfully. Nothing here is on the current path.

Staged and verified on the dev box:

- `driver/prestera-v6.14/` — mainline v6.14 prestera source, patched to bind
  `11ab:7080`, builds clean against 6.14 headers.
- `patches/0001-prestera-add-dev-id-7080.patch` — the same change as a
  reviewable diff that applies to pristine upstream.
- `firmware-refs/mrvl/prestera/` — v2.0/3.0/4.0/4.1 + arm64 v4.1 images,
  decompressed from `linux-firmware`, all five confirmed carrying the
  `0x351D9D06` header magic. The driver asks for v4.1 and falls back to v4.0.
- `scripts/` — run in order:
  1. `00-collect-hw.sh` — read-only PCI/BAR/dmesg capture into `logs/`.
     Run this on the stock live USB first; it also reports the real device
     ID if `0x7080` turns out to be wrong.
  2. `05-stage-firmware.sh` — only if `firmware-refs/` is empty (it is
     gitignored); repopulates it from the `linux-firmware` package.
  3. `10-build-module.sh` — build against the running kernel (needs
     `linux-headers-$(uname -r)` on the appliance).
  4. `20-load-test.sh` — load the driver and interpret the handshake.

Two unknowns are module parameters rather than compile-time guesses, so the
bench loop is `insmod`, not `rebuild`:

- `pp_bar2` — separate BAR4 (AC3X/Aldrin2 style) vs. second half of BAR2
  (98DX35xx style). Unknown for `0x7080`; `00-collect-hw.sh` dumps the BAR
  sizes that decide it.
- `fw_arm64` — which firmware image flavour to request.

Both default to `-1`, which preserves upstream per-device behaviour, so
already-supported chips are unaffected.

`20-load-test.sh` turns dmesg into a verdict. The one that matters:
"waiting for FW loader is timed out" means the loader magic `0xf00dfeed`
never appeared — driver bound, but no Prestera loader at that offset, so
flip `pp_bar2` and retry. "Prestera FW is ready" means `0xcafebabe` came
back and the wire protocol matches.

## Open questions

- [ ] Does the contact who supplied the unit have any additional findings
      since 2023, or extracted firmware for this exact chip variant?
- [x] **Answered**: yes — the `NPU COM` header, separate from the x86 RJ45
      console. See `docs/npu-com-serial-checklist.md`.
- [x] **Answered**: the SFP "F1" port sits behind the **same switch**
      (port 0 or 9 in the init sequence). There is no independent SFP
      path, so no partial win by using SFP alone.

## Repo / write-up plans

Once there's a working result, this follows the same public pattern as
the Cavium project: GitHub repo, OpenWrt forum reply (continuing the 2023
thread), r/homelab post, extended technical writeup, GitHub Sponsors link
in every public post.
