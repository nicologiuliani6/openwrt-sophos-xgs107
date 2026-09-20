# Hardware reference

Observed on an XGS 107w running SFOS 19.5.4 MR-4 (Build 718) and under
OpenWrt. Board silkscreen `XGS 87(W) 107(W) 1.40`
(one PCB for the XGS 87 and 107; the "w" models have the Wi-Fi card).

## Panel and connectors

| | |
|---|---|
| Ports | 8× GbE RJ45 labelled 1/LAN, 2/WAN, 3/DMZ, 4, 5, 6, 7, 8, and one SFP labelled F1 |
| USB | 1× type A on the front. It is the **x86's** (EHCI, high speed; a USB flash drive was detected as `sdb` and read). The CN9130's two xHCI controllers are enabled in the DT, with VBUS switches, but no device was found behind them |
| Console (x86) | RJ45 (Cisco rollover) **and** micro-USB (Prolific PL2303, `067b:23a3`), 38400 8N1; the micro-USB one takes priority. The PL2303 is renumbered `ttyUSBn` at every power cycle: use `/dev/serial/by-id/usb-Prolific*-port0` |
| Console (NPU) | wired to the x86's second UART (I/O `0x3e8`, irq 5): `/dev/ttyS2` under SFOS, `/dev/ttyS1` under OpenWrt; 115200 8N1. The on-board 2×4 `NPU COM` header is unused (it showed no output) |
| Wi-Fi | M.2/mini-PCIe QCA988x (`168c:003c`, ath10k), two U.FL leads to the SMA connectors |
| Power | two DC inputs (redundant) |

## x86 module

| Item | Value |
|---|---|
| CPU / RAM | AMD Embedded R-Series RX-216TD (family 15h, 2 cores), 4 GB |
| Firmware | AMI UEFI, BIOS 2A06; GRUB 2.02 (EFI) on the disk's boot partition |
| Disk | 64 GB SATA flash, MBR |
| PCIe | `02:00.0` Wi-Fi; `03:00.0 [11ab:7080]` the NPU (Gen3 x2, MSI). Under SFOS also two `[11ab:7081]` functions at `03:00.2/3` |
| USB | xHCI + EHCI; a Microchip MCP2210 USB-SPI bridge on an internal hub (Sophos's U-Boot update path) |

SFOS's own drivers for the NPU are `kmod-host-npu_drivers`
(License: Sophos-Proprietary; `mv_armada_drv`, `mv_pport`, `mv_giu_drv`,
`mv_pcinet_drv`, `mv_nwa_host`, `mv_mux_lag`, `mv_nwa_host_mux_lag`),
Linux 4.14.277 only. Under SFOS the ports appear as `Port1…Port8` and `PortF1`
on top of a multiplexed netdev `mv-pcimux0`, plus a management link
`mvmgmt0`; `xgs-ssh.sh "<cmd>"` runs a command as root on the stock NPU.

## NPU module

| Item | Value |
|---|---|
| SoC | Marvell CN9130 (AP807 + CP115), 4× Cortex-A72 |
| Stock board | DT `cn9130-senao-xgs` (ODM: Senao), Marvell SDK Linux 4.14.207, part no. `AMDA0200-0004` |
| RAM | 2 GB usable |
| Storage | SPI NOR: `mtd0` U-Boot (4032 KiB), `mtd1` env (64 KiB). eMMC 7.3 GB, layout below |
| Ethernet | `mvpp2` `eth0`, `10gbase-r`, to switch port 0 |
| Switch | Marvell 88E6193X on MDIO address 2 |
| Endpoint | `pcie@f2600000` (DesignWare, Marvell wrapper), `03:00.0` on the x86 |
| USB | two xHCI (`f2500000`, `f2510000`) with UTMI PHYs; VBUS enables: CP GPIO1 pin 9 and CP GPIO2 pin 21 |
| Console | `ttyS0` `0xf0512000`, 115200 8N1 |

### eMMC (`mmcblk0`, 7.28 GiB)

| Partition | Size | Use |
|---|---|---|
| p1 | 500 MiB | **OpenWrt** (this project); was the oldest Sophos slot |
| p2 | 1.5 GiB | Sophos slot |
| p3 | 1.5 GiB | Sophos slot, the stock boot (`root=/dev/mmcblk0p3`) |
| p4 | 100 MiB | `/persistent` |
| | ~3.7 GiB | unallocated |
| boot0/boot1 | 4 MiB each | eMMC hardware boot partitions, all zero |

### Stock U-Boot environment (relevant parts)

```
bootdelay=3
bootcmd=ext4load mmc 0:3 $kernel_addr_r /boot/Image; ext4load mmc 0:3 $fdt_addr_r /boot/cn9130-senao-xgs.dtb; run fdt_set_partno; booti $kernel_addr_r - $fdt_addr_r
bootcmd_emmc{1,2,3}=  the same for partition 1/2/3
kernel_addr_r=0x7000000   fdt_addr_r=0x6f00000
sw_init_p0=gpio clear C17; sleep 2; gpio set C17; sleep 2         # switch reset (C = CP GPIO2)
sw_init_p1..p3 = mvswitch … writes (port defaults, PHY reset)
```

The stock U-Boot can boot any kernel and DTB from `/boot` of any eMMC slot
and has a `mvswitch` command for the 88E6193X.

`install/uboot-env.txt` adds `bootargs_owrt`, `bootcmd_owrt`,
`bootcmd_stock` and a new `bootcmd`.

## Port map

| Panel | 88E6193X port | Linux name | Type | Speed LEDs (PCA9555 pins, stock `gpio:3:hi:lo`) |
|---|---|---|---|---|
| 1 (LAN) | 1 | `p1` | internal PHY | 1 : 0 |
| 2 (WAN) | 2 | `p2` | internal PHY | 3 : 2 |
| 3 | 3 | `p3` | internal PHY | 5 : 4 |
| 4 | 4 | `p4` | internal PHY | 7 : 6 |
| 5 | 5 | `p5` | internal PHY | 9 : 8 |
| 6 | 6 | `p6` | internal PHY | 11 : 10 |
| 7 | 7 | `p7` | internal PHY | 13 : 12 |
| 8 | 8 | `p8` | internal PHY | 15 : 14 |
| F1 | 9 | `sfp` | SFP cage (SFF-8431) on `i2c1`: EEPROM 0x50, diag 0x51; GPIOs on CP GPIO1: rx_los, tx_fault, present (active low), tx_disable | – |
| CPU | 0 | `eth0` | 10G to the CN9130 `mvpp2` | – |

- The PCA9555 LED expander is at `i2c0` address 0x20. In the DT each pin is
  a `gpio-leds` entry, `green:lan-N` (pin 2N-2) and `amber:lan-N` (pin 2N-1),
  active-low as a guess; the netdev trigger drives the green ones. Which
  colour is which pin, and the polarity, are **not confirmed**.
- The PHY LED control register value is `0xe3` (RJ45) and `0xe1` (SFP) in the
  stock setup; the mainline driver leaves it at the default.
- MACs: 19 consecutive addresses from the label MAC. Ports 1-8 and F1 use
  base+0…8, the backplane base+9/+10 (U-Boot's `ethaddr` is base+9), the x86
  from base+11. OpenWrt derives LAN = label MAC, WAN = label+1 from
  `ethaddr`.

## PCIe endpoint facts (CN9130 ↔ x86)

Link Gen3 x2. The x86 sees BAR0 1 MiB / BAR2 1 MiB (with our function) or
BAR0 1 MiB / BAR2 16 MiB / BAR4 16 MiB (stock, `[11ab:7080]`); BARs are
1 MiB granular. The endpoint controller is standard DesignWare (iATU in
viewport mode, 8 inbound / 8 outbound windows, 64 KiB region alignment) with
Marvell vendor registers at offset `0x8000` (global control, AXI cache
attributes). See [npu-x86-link.md](npu-x86-link.md).
