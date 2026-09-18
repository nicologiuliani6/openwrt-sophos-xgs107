# Prior art — community bring-up of the XGS switch (split-brain)

> **Update 2026-09-18, from our own unit:** the "Marvell 7080 switch chip"
> is a **CN9130 SoC** (PCIe endpoint) plus an **88E6193X** switch. See
> [hardware-architecture.md](hardware-architecture.md). Two readings of the
> post below change:
> - The *"Sophos USB-SPI tool that's on the board"* is SFOS's own
>   `xgs-npu-uboot-update.sh`. It runs on the x86 and writes the NPU's
>   `/dev/mtd0` through `xgs-ssh.sh`, so it is not a separate
>   hardware tool.
> - "CPSS agent" in the post very likely means Sophos's NPU switch agent
>   (NetAgent, `xgs-mdio`), not Marvell's Prestera CPSS: an 88E6193X is not
>   a Prestera device.
>
> The method itself still stands: boot the CN9130 side and the ports
> forward.

**Source**: r/opnsense thread, "finally getting 8 ports working on sophos
xgs 107 under linux" (posted ~May 2026, active through Sept 2026).
<https://www.reddit.com/r/opnsense/comments/1tolc32/finally_getting_8_ports_working_on_sophos_xgs_107/>

**Naming policy**: no usernames, handles or real names appear anywhere in
this repo. Attribution is to "the r/opnsense community" and the thread
link only. Everything below is technical fact and methodology.

**Status of that work**: L2 forwarding confirmed working on all 8 ports.
L3 in progress. A full step-by-step writeup was promised but had not been
published as of the last thread activity. So the *method* is public, the
*recipe* is not — we reconstruct the details ourselves.

---

## 1. The architecture (this is the headline finding)

The XGS is a **split-brain box**. The x86 side you install an OS on is
only half the appliance.

| Side | Detail |
|---|---|
| x86 | Where Debian/OPNsense/OpenWrt gets installed. Sees only the USB ethernet dongle by default. |
| Switch | Marvell **7080**, with its **own ARM CPU, own 2 GB RAM, own eMMC storage**. Boots **its own Linux**, running Marvell's proprietary **CPSS agent** to manage the switch fabric. |

**Without the ARM side booting and running CPSS, the switch forwards zero
packets — no matter what driver is loaded on the x86 side.**

This is why every previous attempt (Debian, OPNsense, OpenWrt) saw no
interfaces at all. It is also why the mainline `prestera_pci.c` device-ID
patch is not the primary solution: it addresses host↔ASIC PCIe
communication, which is not the thing that is missing.

Corroborated independently by the 2023 OpenWrt forum thread on this model,
which states the switch *"operates as a router unto itself (it has its own
ARM processor)"*:
<https://forum.openwrt.org/t/sophos-xgs107-and-no-network-interfaces-unknown-network-controller/168989>

### Scope of the finding

- Reported to apply to **all XGS desktop models — 87, 107, 116, 126, 136**
  — same architecture throughout.
- Older **SG / XG** generation units used Intel chipsets and do **not**
  need any of this.
- The larger rackmount XG/SG 200+ series: untested, unknown.
- Contrast case: on Barracuda F180a/F280a, an alternative OS makes the
  8-port Marvell switch fall back to **dumb-switch mode** — degraded but
  usable. **The XGS does not do this.** No fallback, nothing works. That
  option is off the table here.

---

## 2. Method actually used (four steps)

1. **Serial console to the ARM-side u-boot**, via the `NPU COM` header on
   the board. Plain FTDI USB-to-TTL adapter — *not* an SFP programmer.
2. **Flashed u-boot to the SPI flash**, using *"Sophos's own USB-SPI tool
   that's on the board"*. See open questions — this phrasing is ambiguous
   and is the least-documented step.
3. **Extracted ARM rootfs + kernel + CPSS agent from Sophos firmware.**
   Which image and by what method was not stated. See
   [sophos-firmware.md](sophos-firmware.md).
4. **Pushed the rootfs to the eMMC over serial.** Slow, but it worked.

Then: `ip link set eth0 up` on the ARM side, and traffic forwarded.
Verified with `/proc/net/dev` showing rx/tx counters incrementing on
`eth0` (`tcpdump` was not present in the extracted rootfs). The ARM shell
prompt is `marvell#`.

---

## 3. `NPU COM` pinout (community-reported)

The header is **4 positions**; the reference marks pin 1 "empty". On our
unit all 4 pins are physically fitted, so "empty" means *not used* — pin 1
could be VCC. See the checklist for the photo and measurement notes.

```
pin 1: (empty)
pin 2: GND   ->  FTDI GND
pin 3: RXD   ->  FTDI TXD
pin 4: TXD   ->  FTDI RXD
```

Note this is written **board-side first** and is **already crossed**:
board RXD goes to adapter TXD, board TXD to adapter RXD.

**Still verify with a multimeter before connecting.** This pinout comes
from one unit of one model; board revisions differ, and a mis-connection
can kill the switch ASIC. Procedure:
[npu-com-serial-checklist.md](npu-com-serial-checklist.md).

Practical note from the thread: a fair amount of the difficulty turned out
to be a **broken jumper wire**, not the pinout. Continuity-test the cables
themselves before doubting the header.

---

## 4. Known problems / not yet solved

- **L3 routing** — not achieved at time of writing. L2 only.
- **VLAN configuration does not persist** across reboots.
- **The SFP "F1" port is behind the same switch** — it appears as port 0
  or 9 in the init sequence. This closes an open question in the README:
  there is no independent SFP path, so no partial win by using SFP alone.
- **No published writeup yet.** Exact commands, image versions, and the
  SPI flashing procedure are undocumented.

---

## 5. Open questions to resolve ourselves

- [ ] Exact physical location of the `NPU COM` header on the XGS 107(w)
      board (case must be opened; photograph it into `logs/`).
- [ ] Which SFOS image was the rootfs/kernel/CPSS extracted from, and by
      what method (squashfs/initramfs unpack? Which partition?).
- [ ] What is the *"USB-SPI tool that's on the board"*? Candidate
      readings: a Sophos flashing utility already resident in the stock
      u-boot; a factory USB-to-SPI programming path exposed via a header;
      or a host-side tool that ships in the firmware. Determines whether
      SPI flashing needs external hardware (clip + programmer) or not.
- [ ] Baud rate of the ARM console (untested; 115200 is the likely value —
      the x86 console's 38400 is unrelated).
- [ ] Can the **open** CPSS agent from Marvell's `switchdev-buildroot`
      replace the Sophos-extracted proprietary one? This is the outcome
      most worth aiming for — it removes the proprietary dependency and
      makes an OpenWrt image legally redistributable.

---

## 6. Related public resources (verified)

Marvell's own open-source switching stack — the legal alternative to
extracted Sophos binaries:

- **switchdev-buildroot** — builds the prestera kernel driver, the CPSS
  drivers, **and a CPSS agent binary**. Most relevant repo for our ARM
  side. <https://github.com/Marvell-switching/switchdev-buildroot>
- **switchdev-prestera** — driver + wiki. Confirms the driver is
  firmware-based over PCI; offloads VLAN-aware/unaware bridge, FDB, LAG,
  STP, LLDP, IPv4 routing, ECMP, VRRP, ACL, devlink traps.
  <https://github.com/Marvell-switching/switchdev-prestera>
- **mrvl-prestera** — interrupt, DMA, MBUS, ethernet drivers.
  <https://github.com/Marvell-switching/mrvl-prestera>
- **dentproject/dentOS** — Linux NOS built on Prestera + switchdev.
  <https://github.com/dentproject/dentOS>
- Third-party guide: building Linux + CPSS on a Marvell Prestera DX
  reference board — closest public step-by-step for the ARM side.
  <https://dev.to/ivan_kuten/linux-and-cpss-assembly-on-marvell-board-with-prestera-dx-switch-1agg>

No GitHub repo specific to XGS switch bring-up exists yet.

**Licensing**: the CPSS agent and SFOS ARM userland are Sophos/Marvell
proprietary. Using them on the hardware they shipped on is defensible;
redistributing them is not. **Do not commit any extracted binary to this
repo.**
