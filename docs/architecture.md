# Architecture

The XGS 107w is two computers in one box. Sophos's firmware hides that; the
project's job is to make both run OpenWrt and behave as one router.

```
   x86 module                              NPU module
 ┌────────────────────────┐   PCIe     ┌──────────────────────────┐  10GBASE-R   ┌────────────┐
 │ AMD RX-216TD, 4 GB     │◄──────────►│ Marvell CN9130           │◄────────────►│ 88E6193X   │── ports 1-8 (RJ45)
 │ 64 GB SATA flash       │  x2 Gen3   │ 4× Cortex-A72, 2 GB      │  mvpp2 eth0  │ switch     │── port 9 = SFP "F1"
 │ Wi-Fi QCA988x (ath10k) │  (NPU is   │ 7.3 GB eMMC, 4 MB SPI    │  ↔ port 0    │ (mv88e6xxx)│
 │ OpenWrt x86/64         │  the       │ OpenWrt mvebu/cortexa72  │              └────────────┘
 │ ntb0 = 192.168.1.2     │  endpoint) │ router: 192.168.1.1, USB │
 └────────────────────────┘            └──────────────────────────┘
   console: 38400 8N1                    console: 115200 8N1 = x86 UART 0x3e8
```

## What runs where

| | NPU (CN9130) | x86 |
|---|---|---|
| OS | OpenWrt `mvebu/cortexa72`, kernel 6.18, from eMMC slot p1 | OpenWrt `x86/64`, kernel 6.18, from the internal disk |
| Role | **The router**: DSA over the 88E6193X (ports p1..p8, sfp), NAT, DHCP, firewall, LuCI, USB | **The Wi-Fi access point** and a second LuCI; bridged to the NPU's LAN |
| Address | `192.168.1.1` (LAN), DHCP on panel port 2 (WAN) | `192.168.1.2` |
| Boot | stock U-Boot (SPI) → `/boot/Image` on eMMC p1, fallback to the stock Sophos slot p3 | stock UEFI → GRUB on disk partition 1 → `/openwrt/vmlinuz`, root on partition 3 |

The two are independent operating systems. What ties them is one virtual
Ethernet link (`ntb0` on both) over the PCIe connection, see
[npu-x86-link.md](npu-x86-link.md). Traffic from Wi-Fi clients goes
`wlan → x86 br-lan → ntb0 → NPU br-lan → switch`.

## Why it is built this way

- The switch chip is a **Marvell 88E6193X** on the CN9130's MDIO bus, and
  its port 0 is a 10 Gb/s link to the CN9130's `mvpp2`. Everything on the
  NPU side (CN9130, `mvpp2`, `sdhci-xenon`, `mv88e6xxx` DSA, SFP) is in
  mainline Linux, so no blobs are needed. L2 switching stays in the
  switch hardware; routing runs on four A72 cores behind a 10G uplink.
- Under SFOS the x86 reaches the ports only through Sophos-proprietary kernel
  modules (`mv_armada_drv`, `mv_pcinet_drv`, …, Linux 4.14.277 only). That
  is why a stock Linux or OpenWrt on the x86 sees no ports.
- The CN9130 is wired to the x86 as a **PCIe endpoint** (that is what
  `03:00.0 [11ab:7080]` is). Mainline Linux has a DesignWare endpoint
  driver and a virtual-NTB endpoint function; with two small patches they
  give the x86 an Ethernet device without any Sophos code.
- The Wi-Fi card sits on the x86's PCIe bus, so the access point has to run
  there.

## NPU boot chain

```
SPI NOR (mtd0) U-Boot 2019.10 (Marvell)  ← never written by this project
  env in mtd1 (64 KiB), bootdelay 3
  bootcmd = run bootcmd_owrt; run bootcmd_stock
    bootcmd_owrt : run sw_init_p0            # pulse the 88E6193X reset (CP GPIO2 17)
                   ext4load mmc 0:1 /boot/Image + /boot/cn9130-sophos-xgs107w.dtb; booti
    bootcmd_stock: boot the Sophos slot p3 as before
eMMC: p1 500 MiB OpenWrt | p2 1.5 GiB stock | p3 1.5 GiB stock | p4 100 MiB /persistent
```

If OpenWrt's kernel cannot be loaded, U-Boot runs the stock command. A
kernel that loads but hangs does not fall back: recovery is then through
the U-Boot prompt ([recovery.md](recovery.md)). The switch is reset by
U-Boot (`sw_init_p0`) and again by the driver (`reset-gpios` in the device
tree).

## x86 disk layout

SFOS's disk has only two entries in the MBR; the rest (`/dev/boot`, `/dev/swap`,
`/dev/var`, sda3…sda9) SFOS creates itself at run time. The installer:

- writes the OpenWrt root filesystem over SFOS's swap area (3.8 GB) and adds
  a real MBR entry **#3** for it (sector 0 backed up as `/boot/mbr-sda.bak`);
- puts the kernel in `/boot/openwrt/` on the existing boot partition
  (`sda1`, ext4, holds GRUB) and adds an `OpenWrt` entry, the default
  (`root=/dev/sda3 console=ttyS0,38400n8 …`).

**SFOS must never be booted again**: it runs `mkswap` on that area at every
boot. Its GRUB entries stay but are a dead end.

## Boot order and failure coupling

Either side can boot first: the x86 runs `ntb-link-wait`, which rescans PCI
until the NPU's function appears. The coupling in the other direction is
harsh: **resetting or losing the NPU while the x86 has the link bound
reboots the x86** (the endpoint disappears under an active driver). It
comes back by itself and re-links.
