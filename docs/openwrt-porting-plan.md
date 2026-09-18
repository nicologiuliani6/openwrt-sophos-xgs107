# OpenWrt on the XGS 107w — porting plan

> **Rewritten 2026-09-18** after identifying the hardware
> ([hardware-architecture.md](hardware-architecture.md)). The previous plan
> ("`x86/64` plus a coprocessor payload package") is superseded.
>
> **Status: final goal. It starts after Phase 2 (mainline Linux booting on
> the CN9130 with working DSA ports).**

## Target: OpenWrt on the CN9130, not on the x86

| | OpenWrt on CN9130 (**chosen**) | OpenWrt on x86 |
|---|---|---|
| Port drivers | mainline `mvpp2` + `mv88e6xxx` DSA | Sophos-proprietary host `.ko`, kernel 4.14.277 only |
| L2 switching | in 88E6193X hardware | through PCIe to the x86 |
| Routing CPU | 4× Cortex-A72 behind a 10G uplink | 2-core RX-216TD |
| Redistributable image | yes | no (blobs) |
| Wi-Fi (QCA988x) | not reachable (it sits on the x86) | yes |

The x86 and its Wi-Fi come in an optional later phase.

## Closest existing OpenWrt devices (target `mvebu/cortexa72`)

Checked in `target/linux/mvebu/image/cortexa72.mk` (OpenWrt `main`):

- **`solidrun_clearfog-pro`**, `SOC := cn9130` — same SoC. Reference for
  the CN9130 DT include chain, eMMC and image layout.
- **`mikrotik_rb5009*`** — Armada 7040 with an **88E6393X** switch on a 10G
  `mvpp2` port through DSA. The same switch family and the same CPU-port
  topology as ours. Reference for the DSA node, SFP on a switch port, and
  `board.d` port naming.
- `iei_puzzle-m901/m902` (CN9131/CN9132) — more CN913x references.

No new target or subtarget is needed: this is one new device in an
existing, maintained target.

## Work items

1. **DTS** `cn9130-sophos-xgs107w.dts`, written and proven in Phase 2:
   - UART0, eMMC, SPI NOR (read-only);
   - `mvpp2` port 0 in `10gbase-kr` to switch port 0;
   - 88E6193X on MDIO address 2: ports 1-8 internal PHYs, port 9 SFP
     (`i2c1`, GPIOs from the port map);
   - switch reset GPIO (u-boot `gpio C17`) and the LED GPIO expander
     (`gpio:3:*`).
2. **Device profile** `sophos_xgs107w` in `cortexa72.mk`, plus DTS in
   `target/linux/mvebu/files*/…/marvell/`.
3. **Image**: the stock u-boot loads `/boot/Image` and
   `/boot/cn9130-senao-xgs.dtb` via `ext4load mmc 0:N`. The first image is
   therefore an ext4 rootfs for a spare eMMC slot, with kernel and DTB under
   `/boot`. **No u-boot replacement.** Later: sysupgrade support that writes
   the inactive slot and flips `bootcmd` (A/B).
4. **`board.d`**:
   - `02_network`: `lan1`…`lan8` mapped to front labels 1…8, `sfp` on F1;
   - default roles: 1 = LAN, 2 = WAN (panel labels 1/LAN, 2/WAN, 3/DMZ).
   - MACs from the base address (stock `ethaddr` and label).
5. **LEDs** via the GPIO expander.
6. **Install and recover**:
   - install: repeated manual boots from the u-boot console (x86
     `/dev/ttyS2`), then `fw_setenv bootcmd` to the OpenWrt slot;
   - recover: interrupt u-boot (`bootdelay=3`), then
     `run bootcmd_emmc3` (stock);
   - full stock restore: from the Phase 1 dumps.
7. **Upstream**: the DTS goes to mainline Linux and the device to OpenWrt.

## Risks

| Risk | Mitigation |
|---|---|
| 10GBASE-KR CPU link needs comphy/serdes setup that mainline lacks for this board | compare with the stock DTB and u-boot `sw_init_*`; the RB5009 uses a similar 10G link |
| 88E6193X quirks (port 0/9 serdes init, `mvswitch dev_write` values in u-boot) | reproduce the stock init values; check `mv88e6xxx` 6393X support in the chosen kernel |
| SFOS daemons on the x86 "repair" a non-stock NPU | run experiments with the x86 on a live Linux, not SFOS |
| Losing the stock image | Phase 1 dumps with sha256 before any write; never write `mtd0` |
