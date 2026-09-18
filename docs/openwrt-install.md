# Installing OpenWrt on the XGS 107w NPU (CN9130)

OpenWrt runs on the **CN9130 NPU**, not on the x86. It is installed into
eMMC slot **p1** (500 MiB, the oldest Sophos rootfs slot). Sophos's
slots p2/p3 and the SPI U-Boot are left untouched, so stock stays one
U-Boot command away.

Everything here is driven from the x86's SFOS console (micro-USB
PL2303, 38400 8N1, advanced shell = menu 5 → 3), using the stock NPU Linux
(`xgs-ssh.sh`). Prerequisite: the verified backups in
[dumps-manifest.md](dumps-manifest.md).

## What is written

| Target | Change | Undo |
|---|---|---|
| eMMC `mmcblk0p1` | OpenWrt ext4 slot image (rootfs + `/boot/Image` + `/boot/cn9130-sophos-xgs107w.dtb`) | `dumps/npu/parts/p1.img` |
| SPI `mtd1` (U-Boot env) | new `bootcmd` (OpenWrt first, stock as fallback), plus `bootcmd_stock`, `bootcmd_owrt`, `bootargs_owrt` | `dumps/npu/mtd1-uboot-env.bin`, or `fw_setenv bootcmd "$bootcmd_stock"` |
| SPI `mtd0` (U-Boot) | **nothing** | — |

## U-Boot environment

```
bootargs_owrt=console=ttyS0,115200n8 earlycon=uart8250,mmio32,0xf0512000 rootwait root=/dev/mmcblk0p1 rw
bootcmd_owrt=run sw_init_p0; setenv bootargs ${bootargs_owrt}; ext4load mmc 0:1 ${kernel_addr_r} /boot/Image && ext4load mmc 0:1 ${fdt_addr_r} /boot/cn9130-sophos-xgs107w.dtb && booti ${kernel_addr_r} - ${fdt_addr_r}
bootcmd_stock=setenv bootargs ${bootargs_emmc3}; <the original bootcmd: boots Sophos slot p3>
bootcmd=run bootcmd_owrt; run bootcmd_stock
```

- `sw_init_p0` is the stock script that pulses the 88E6193X reset (CP
  GPIO2 17). The mainline driver needs the switch fresh, see
  [bench-log.md](bench-log.md) §13.
- If OpenWrt's kernel or DTB cannot be loaded, `bootcmd` falls through to
  stock Sophos.

## Back to stock

- From OpenWrt: `fw_setenv bootcmd "$(fw_printenv -n bootcmd_stock)"`,
  then reboot.
- From the U-Boot prompt: the NPU console is x86 `/dev/ttyS2` @ 115200.
  Interrupt autoboot (3 s) and type `run bootcmd_stock`.
- Full factory state: restore `mmcblk0p1` and `mtd1` from the dumps.

## Using it

- Panel **port 2 = WAN** (DHCP client). Ports 1, 3-8 and the SFP = LAN
  bridge, **192.168.1.1**, DHCP server on.
- LuCI: plug a PC into a LAN port and open http://192.168.1.1 (user
  `root`, no password until you set one).
- The x86 side is independent. SFOS on it cannot reach its NPU anymore and
  stays in failsafe. It does not reflash the NPU in that case (see
  `npu_host_validation.sh`, failure reason 1).
