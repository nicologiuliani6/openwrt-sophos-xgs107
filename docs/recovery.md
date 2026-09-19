# Recovery

## Getting a console

| What | How |
|---|---|
| x86 | micro-USB (PL2303) or RJ45 console, 38400 8N1. Use the `by-id` path: `ttyUSBn` changes at every power cycle |
| NPU | from the x86: `stty -F /dev/ttyS2 115200 raw -echo; cat /dev/ttyS2` (or `picocom -b 115200 /dev/ttyS2`). Works from OpenWrt on the x86 and from SFOS |
| Both, from the PC | `tools/console-send.py` (send lines, print the reply), `tools/console-log.py` (log across power cycles) |

The NPU's U-Boot waits 3 seconds (`bootdelay`): press a key on the NPU
console right after a power-up to get the prompt.

## The NPU does not boot OpenWrt

- **U-Boot could not load `/boot/Image` or the DTB**: it falls back to
  stock by itself.
- **The kernel loads and hangs or panics**: at the NPU U-Boot prompt
  (console above): `run bootcmd_stock` boots Sophos slot p3; then, from
  there, `fw_setenv bootcmd "$(fw_printenv -n bootcmd_stock)"` makes stock the
  default again. To retry OpenWrt with a known-good kernel replace
  `/boot/Image` and the DTB on p1.
- **Make stock the default from a working OpenWrt**:
  `fw_setenv bootcmd "$(fw_printenv -n bootcmd_stock)"`, reboot.
- **Everything, factory state**: restore `mtd1` (env) and `mmcblk0p1` from the
  backup ([backup.md](backup.md)); the SPI U-Boot is never modified.

## The x86 does not boot OpenWrt

The x86 has no display; everything is on the serial console.

- GRUB shows a menu for 5 s at 38400 baud; the default is `OpenWrt`.
  `tools/x86-grub.py` catches that window from the PC and can type a kernel
  command line for you (GRUB at this speed drops characters in its editor;
  the tool uses the command line, `c`, and checks the screen).
- **If SFOS booted**: shut it down at once and boot the `OpenWrt` entry.
  SFOS runs `mkswap` on the OpenWrt partition at boot, so a completed SFOS
  boot means the OpenWrt root is gone: reinstall (`install-x86.sh`, needs the
  NPU on stock, see below).
- **Back to SFOS** (destructive for OpenWrt): restore the MBR
  (`dd if=/boot/mbr-sda.bak of=/dev/sda bs=512 count=1`), `grub.cfg.sfos` over
  `grub.cfg`, both in the boot partition; or reinstall SFOS from Sophos's
  installer ISO on a USB stick ([reference/sophos-firmware.md](reference/sophos-firmware.md)).

## Reinstalling the x86 later

`install-x86.sh` downloads through the NPU, which under OpenWrt is the router:
run it from any Linux on the x86 that has network. If the x86 is unbootable,
boot the NPU on stock (`run bootcmd_stock` at its U-Boot prompt) and use SFOS's
network as at install time.

## Lost SFOS admin password (needed only at install time)

Sophos's documented console reset: at the console `Password:` prompt type
`RESET`, choose **4. Reset password for admin user** in the hidden menu and
confirm with `y`; then log in as `admin` with the factory password `admin`.
Options 1-3 of that menu are full factory resets: do not use them. Reinstalling is not needed.

## Rescue tips learnt the hard way

- `dd of=<node>` on a node that does not exist creates a regular file in
  RAM. `install-x86.sh` checks `[ -b /dev/swap ]` and verifies through
  `/dev/sda`; do the same for any manual write.
- Resetting the NPU reboots the x86 (its PCIe endpoint vanishes under a
  bound driver). It recovers alone; wait two minutes.
- `pkill -f <pattern>` kills your own shell when the pattern is in its
  command line.
