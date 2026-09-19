# Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `install-x86.sh`: `/dev/swap is not a block device` | SFOS is not in its normal state; reboot SFOS once, open the advanced shell again. **Never** `dd of=/dev/sda8`: SFOS has no such node and `dd` silently writes a file into RAM |
| `install-x86.sh`: `raw disk read-back mismatch` | the write did not reach the disk. Nothing else was changed (the MBR entry comes after the check); run it again |
| `install-npu.sh`: `the NPU is not running the stock Linux 4.14` | the NPU already runs OpenWrt or did not boot; the installer only works against stock. Boot stock (`run bootcmd_stock` at the NPU's U-Boot prompt) and run the installer again, see [recovery.md](recovery.md) |
| x86 boots SFOS after the install | the GRUB default was not changed or SFOS's `grub.cfg` was regenerated: pick `OpenWrt` in the menu, then `install-x86.sh` again. If SFOS finished booting, its `mkswap` erased the OpenWrt root: reinstall |
| x86 has no network / no `ntb0` | `lspci -nn -s 03:00.0` should say `[1957:0809]`; if it says `[11ab:7080]` the NPU is still in U-Boot or on stock. The NPU must be running OpenWrt (`/etc/init.d/vntb` started). `ntb-link-wait` retries every 5 s; force it with `echo 1 > /sys/bus/pci/devices/0000:03:00.0/remove; echo 1 > /sys/bus/pci/rescan` |
| x86 log: `AMD-Vi: IO_PAGE_FAULT … address=0x0` | the host is using MSI-X; the x86 kernel is missing patch 953 |
| `ntb_hw_epf: Unsupported MW count: 32…` | the NPU side's BAR memory is not 1 MiB aligned: NPU kernel without patch 951 |
| `Failed to configure doorbell` (`-110`) | the endpoint does not see the host's writes: BAR alignment (951) or a `dma-coherent` endpoint node |
| NPU ↔ x86 only 5–15 Mbit/s | `transport_mtu=2048` is missing on one side: `cat /sys/module/ntb_transport/parameters/transport_mtu` must be 2048 on both (it is set in `/etc/modules.d/ntb-*` by the first-boot script) |
| NPU: `88e6xxx … -ETIMEDOUT` or the switch does not probe | the switch did not come out of reset: check `reset-gpios` (CP GPIO2 pin 17) in the device tree and `run sw_init_p0` in `bootcmd_owrt` |
| NPU `mv88e6085 … PTP clock unavailable` | expected; patch 950 lets the switch work without hardware timestamping |
| NPU boots into a RAM root, `/boot` missing, config lost | the wrong kernel was installed: the `Image` out of a full OpenWrt build is the *initramfs* kernel (28 MB). `build/mk-emmc-slot.sh` uses the plain one (14 MB); when replacing a kernel by hand use the one from `linux-mvebu_cortexa72/sophos_xgs107w-kernel.bin` |
| The x86 reboots when the NPU restarts | expected, see [architecture.md](architecture.md) |
| GRUB over the serial console drops characters | it does at 38400 baud in its editor; use its command line (`c`) or `tools/x86-grub.py` |
| `/dev/ttyUSB0` does not exist | the PL2303 is renumbered at each power cycle; use `/dev/serial/by-id/usb-Prolific*-port0` |
| LEDs dark or inverted | polarity and colours are a guess, see [usage.md](usage.md) |
| `resize2fs` on the x86 root fails ("add group #5") | not needed: the image already fills the partition (3.7 GB) |
