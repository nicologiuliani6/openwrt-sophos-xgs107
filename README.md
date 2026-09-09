# Sophos XGS 107w — Marvell Prestera reverse engineering

Reviving a Sophos XGS 107w desktop firewall appliance whose built-in 8-port
Marvell switch ASIC has no working open source driver. Goal: get the switch
ports functional under Linux/OpenWrt without Sophos's proprietary SFOS.

Hardware received as a gift from a contact (NC1HM), likely the same "NC1"
who diagnosed this exact problem on the OpenWrt forum in 2023.

## Hardware facts (confirmed)

- **Platform**: x86, AMD-based (per the 2023 OpenWrt thread `lspci` dump —
  needs reconfirming on this exact unit once it arrives)
- **Switch chip**: Marvell Technology Group, PCI ID `[11ab:7080]`
- **Ports**: 8x GbE copper (1/LAN, 2/WAN, 3/DMZ, 4, 5, 6, 7, 8) + 1x SFP
  (labeled "F1")
- **Wi-Fi**: integrated ("w" model), 2x SMA antenna connectors — chipset
  not yet identified, may work out of the box independent of the switch
  problem
- **USB**: USB 3.0 port, standard xHCI, should work with any Linux out of
  the box
- **Power**: dual redundant DC IN (DC IN 1 / DC IN 2)
- **Console**: RJ45, Cisco-style rollover pinout, **38400 baud, 8N1**
  (confirmed by NC1HM directly)
- **Rack mount**: not included; third-party kits exist (Rackmount.IT
  RM-SR-T11, ~1.3U) if ever needed — not required for bring-up work

## The core problem

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

OpenWrt forum thread, user "pancio" tried this exact model, got nothing
(no network interfaces at all — worse than a dumb switch fallback). User
"NC1" explained why: no driver existed publicly at the time for this
switch family with the level of detail needed. Netgate had written a
similar driver but kept it proprietary inside pfSense Plus.

Since 2023, the mainline `prestera` driver + public firmware situation
described above has matured significantly — this may no longer be a dead
end. That's the bet this project is making.

Source: https://forum.openwrt.org/t/sophos-xgs107-and-no-network-interfaces-unknown-network-controller/168989

## First steps once the hardware arrives

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

## Ready before the hardware arrives

Everything for step 4 above is staged and verified on the dev box — nothing
left to figure out at the bench:

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

- [ ] Does NC1HM (possibly = forum user "NC1") have any additional
      findings since 2023, or leaked/extracted firmware for this exact
      chip variant?
- [ ] Is there a hidden debug UART near the Marvell chip itself (separate
      from the x86 BIOS console), for visibility into the switch's ARM
      core specifically?
- [ ] Does the SFP "F1" port sit behind the same switch, or is it wired
      independently?

## Repo / write-up plans

Once there's a working result, this follows the same public pattern as
the Cavium project: GitHub repo, OpenWrt forum reply (continuing the 2023
thread), r/homelab post, extended technical writeup, GitHub Sponsors link
in every public post.
