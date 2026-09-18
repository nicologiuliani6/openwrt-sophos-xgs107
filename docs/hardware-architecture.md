# Hardware architecture (confirmed from the running unit)

Everything here was read from a live XGS 107w running SFOS 19.5.4 MR-4
(Build 718), via the x86 console and SFOS's own management tooling. Raw
output: `logs/sfos-recon-20260918.log`. How it was obtained:
[bench-log.md](bench-log.md), session 1 §7.

This supersedes the earlier assumption that `[11ab:7080]` is a Prestera
switch ASIC. It is not.

## Block diagram

```
   x86 host (SFOS)                         NPU complex
 ┌──────────────────────┐   PCIe      ┌────────────────────────┐   10GBASE-KR   ┌──────────────┐
 │ AMD RX-216TD, 2 core │◄──────────► │ Marvell CN9130         │◄──────────────►│ Marvell      │── ports 1-8 (RJ45)
 │ 4 GB RAM             │  (CN9130 is │ 4× Cortex-A72, ~1.5 GB │ mvpp2 eth0 ↔   │ 88E6193X     │── port 9 → SFP "F1"
 │ Wi-Fi QCA988x ath10k │  PCIe EP)   │ eMMC 7.3 GB, SPI 4 MB  │ switch port 0  │ (mv88e6xxx)  │
 └──────────────────────┘             └────────────────────────┘                └──────────────┘
   console: ttyS0 38400                 console: ttyS0 115200
   (RJ45 + micro-USB PL2303)            = x86 /dev/ttyS2
```

## x86 host

| Item | Value |
|---|---|
| CPU | AMD Embedded R-Series RX-216TD (PCI IDs `1022:157x`) |
| RAM | 4 GB |
| Kernel (SFOS) | 4.14.277, cmdline `console=ttyS0,38400n8 amd_iommu=on iommu=pt …` |
| Wi-Fi | `02:00.0 [168c:003c]` Qualcomm Atheros QCA988x, `ath10k_pci` |
| NPU on PCIe | `03:00.0 [11ab:7080]` bound to `armada_pci` (`mv_armada_drv`); `03:00.2` and `03:00.3 [11ab:7081]` bound to `vfio-pci` (SFOS userspace fast path) |

Host-side NPU drivers, package `kmod-host-npu_drivers`
(`4.14.277+2023.1024-1906-v19.5.Maint.080`, **License: Sophos-Proprietary**,
source path `package/sfos/npuos/host-npu_drivers`), in
`/lib/modules/4.14.277/extra/`:

`mv_armada_drv`, `mv_pport`, `mv_giu_drv` (~1.1 MB), `mv_pcinet_drv`,
`mv_nwa_host`, `mv_mux_lag`, `mv_nwa_host_mux_lag`.

The x86 sees the front-panel ports as sub-interfaces of one PCIe netdev:

| x86 netdev | Meaning |
|---|---|
| `mv-pcimux0` | multiplexed PCIe data interface (MTU 9216) |
| `Port1`…`Port8`, `PortF1` `@mv-pcimux0` | front-panel ports |
| `pport_l0`, `pport_l0s0p0`, `pport_l254` | internal logical ports |
| `mvmgmt0` (flag `NPUMGMT`) | management link to the NPU Linux, IPv6 link-local only |

The NPU's address on `mvmgmt0` comes from `xgs-arm-ip6-addr.sh`.
`xgs-ssh.sh "<cmd>"` runs a command **as root on the NPU**. SFOS manages
the NPU entirely through this path.

## NPU: Marvell CN9130

| Item | Value |
|---|---|
| SoC | CN9130 (AP807 + CP115), 4× Cortex-A72 (`0xd08` r0p3) |
| Board | DT model `Marvell CN9130 Senao XGS board`, DTB `cn9130-senao-xgs.dtb` (ODM: Senao) |
| RAM | ~1.5 GB usable |
| Kernel | Linux 4.14.207-10.22.03 (Marvell SDK 10.22.03), aarch64 |
| Console | `ttyS0` @ `0xf0512000`, 115200 8N1 — wired to x86 `/dev/ttyS2` |
| PCIe | `armada-pcie-ep f2600000.pcie-ep` — endpoint towards the x86 |
| Ethernet | `mvpp2 f2000000.ethernet eth0`, `10gbase-kr` in-band, to switch port 0 |
| Mgmt | `mvmgmt0` (PCIe management netdev) |
| Assembly | part no. `AMDA0200-0004` rev 08 → SFOS platform `xgsdt1` |

### Storage

SPI NOR (`/proc/mtd`):

| mtd | Size | Name |
|---|---|---|
| mtd0 | 0x3F0000 (4032 KiB) | `U-Boot` |
| mtd1 | 0x10000 (64 KiB) | `U-Boot-env` |

eMMC `mmcblk0`, 7.28 GiB (`8GTF4R`, HS200):

| Partition | Size | Use |
|---|---|---|
| p1 | 500 MiB | rootfs slot (`bootcmd_emmc1`) |
| p2 | 1.5 GiB | rootfs slot (`bootcmd_emmc2`) |
| p3 | 1.5 GiB | rootfs slot (`bootcmd_emmc3`) — **active** (`root=/dev/mmcblk0p3`) |
| p4 | 100 MiB | `/persistent` |
| boot0 / boot1 | 4 MiB each | eMMC HW boot partitions |

### u-boot environment (relevant parts)

```
bootdelay=3
bootcmd=ext4load mmc 0:3 $kernel_addr_r /boot/Image; ext4load mmc 0:3 $fdt_addr_r /boot/cn9130-senao-xgs.dtb; run fdt_set_partno; booti $kernel_addr_r - $fdt_addr_r
bootcmd_emmc{1,2,3}= same, for partition 1/2/3
bootargs=console=ttyS0,115200n8 earlycon=uart8250,mmio32,0xf0512000 rootwait ro pci=pcie_bus_safe root=/dev/mmcblk0p3 cpuidle.off=1 isolcpus=1-3 nohz_full=1-3 rcu_nocbs=1-3
kernel_addr_r=0x7000000   fdt_addr_r=0x6f00000
fdt_set_partno=fdt addr $fdt_addr_r; fdt set /usfp_rh assembly_partno $partno
sw_init_p0=gpio clear C17; sleep 2; gpio set C17; sleep 2          # switch reset
sw_init_p1=for i in '0 1 2 3 4 5 6 7 8 9' ; do mvswitch 2 write $i 4 0x7f ; done
sw_init_p2=for i in '0 9'; do mvswitch 2 dev_write $i 4 f002 804d ; mvswitch 2 dev_write $i 4 2000 9140 ; done
sw_init_p3=for i in '1 2 3 4 5 6 7 8' ; do mvswitch 2 phy_write $i 0 0 9140 ; done
sw_init_2=run sw_init_p0; run sw_init_p1; run sw_init_p2; run sw_init_p3
```

The stock u-boot can already boot any kernel and DTB from `/boot` on any
of the three eMMC slots, and it has a `mvswitch` command for the 6193X.

## Switch: Marvell 88E6193X

- On MDIO, `mdio22:0:2` (clause-22 bus 0, SMI address 2).
- Supported by mainline Linux `mv88e6xxx` (6393X family) and hence DSA.
- In stock SFOS the NPU kernel has **no DSA**. The switch is driven from
  userspace ("NetAgent", `xgs-mdio`).

### Port map (from `xgs-platform`)

| Front label | 6193X port | Type | Speed LED GPIOs |
|---|---|---|---|
| 1 | 1 | internal PHY, RJ45 | `gpio:3:1:0` |
| 2 | 2 | internal PHY, RJ45 | `gpio:3:3:2` |
| 3 | 3 | internal PHY, RJ45 | `gpio:3:5:4` |
| 4 | 4 | internal PHY, RJ45 | `gpio:3:7:6` |
| 5 | 5 | internal PHY, RJ45 | `gpio:3:9:8` |
| 6 | 6 | internal PHY, RJ45 | `gpio:3:11:10` |
| 7 | 7 | internal PHY, RJ45 | `gpio:3:13:12` |
| 8 | 8 | internal PHY, RJ45 | `gpio:3:15:14` |
| F1 | 9 | SFP (SFF-8431), serdes | — |
| — (CPU) | 0 | 10G serdes to CN9130 `eth0` (mvpp2 port 0) | — |

The SFP cage sits on `i2c1`: EEPROM `0x50`, diagnostics `0x51`. Its GPIOs
are on chip 1: `rx_los` 1, `tx_fault` 2, `present` 3 (active low),
`tx_disable` 7. PHY LED control register value `0xe3` (RJ45), `0xe1` (SFP).

Backplane `bp0`: CN9130 port `0:0` ↔ 6193X port `1:0`, 10G. Flow
control: RX only on the CN9130 side, TX+RX on the switch side.

MACs: 19 consecutive addresses from the base on the label. Ports 1-8 and
F1 use base+0 … base+8, the backplane base+9/+10, the x86 base+11 onward.

## Consequences

- The split-brain model stands, but the components are a **CN9130 SoC
  plus an 88E6193X switch**, not a Prestera. The mainline `prestera`
  driver, the `0x7080` device-ID patch and the linux-firmware Prestera
  images are **not relevant**.
- The NPU complex is made of parts that mainline Linux supports: CN9130
  (`cn9130.dtsi`), `mvpp2`, `sdhci-xenon`, `mv88e6xxx` DSA, SFP. So running
  mainline Linux, and then OpenWrt, **on the CN9130 itself** is the
  primary path. See [openwrt-porting-plan.md](openwrt-porting-plan.md).
- The NPU console needs no hardware hacking: it is x86 `/dev/ttyS2` @
  115200. Why the `NPU COM` header read nothing on the bench is still
  unexplained (level? mux?), but it no longer matters.
