# Backing up the stock system

Do this before installing. `install/backup-stock.sh` streams everything to
the PC (nothing is stored on the appliance); the receiver refuses to
overwrite an existing file and prints the sha256 of each stream.

```sh
# PC, in the repository
python3 tools/dump-receiver.py 8001          # writes into dumps/  (gitignored)
install/serve.sh                              # second terminal, port 8000; prints the PC's address
# x86 SFOS advanced shell (PC = the address serve.sh printed; the stock NPU must be running)
curl -fsS http://PC:8000/backup-stock.sh -o /dev/shm/b.sh && PC=PC PORT=8001 sh /dev/shm/b.sh
```

`SKIP_EMMC=1` (put it before `PC=` in the command above) leaves out the whole-eMMC copy (7.3 GB, about 25 minutes).
Keep at least the SPI U-Boot, its environment and the stock slot p3.

What you get in `dumps/`:

| File | Source |
|---|---|
| `npu/mtd0-uboot.bin` | SPI U-Boot (4032 KiB): the last-resort copy, this project never writes it |
| `npu/mtd1-uboot-env.bin` | U-Boot environment |
| `npu/running.dtb` | the stock device tree, `/sys/firmware/fdt` |
| `npu/mmcblk0boot0.bin`, `…boot1.bin` | eMMC hardware boot partitions (all zero on the reference unit) |
| `npu/mmcblk0-full.img` | the whole eMMC, including the partition table |
| `npu/partitions-and-env.txt` | `fdisk -l` and `fw_printenv` |
| `x86/sda-first-1M.bin`, `x86/boot-partition.img` | MBR and the boot partition (GRUB, SFOS kernels) |

The proprietary Sophos/Marvell content stays out of git: `dumps/` is ignored.

## Verify

Compare the receiver's sha256 lines with the NPU's own (the script prints
`sha256sum` of each device):

```
sha256sum /dev/mtd0 /dev/mmcblk0 ...        # on the NPU, printed by the script
sha256sum dumps/npu/mtd0-uboot.bin ...      # on the PC
```

They must match byte for byte. For a partial check of the eMMC copy:
`fdisk -l dumps/npu/mmcblk0-full.img` must show p1…p4.

## Restore

- **A single eMMC slot** (for example back to stock in p1): from a running
  NPU Linux, stream the partition back:
  `curl http://PC:8000/p1.img | xgs-ssh.sh "dd of=/dev/mmcblk0p1 bs=1M conv=fsync"`
  (cut it from the full image: `dd if=mmcblk0-full.img bs=512 skip=2048 count=1024000 of=p1.img`).
- **U-Boot environment**: `fw_setenv` the variables you changed back, or
  from OpenWrt `fw_setenv bootcmd "$(fw_printenv -n bootcmd_stock)"`.
- **SPI U-Boot** (only if it was damaged, which this project cannot do):
  write `mtd0-uboot.bin` back with Sophos's own `xgs-npu-uboot-update.sh`
  path or an SPI programmer.
- **x86 MBR**: `dd if=/boot/mbr-sda.bak of=/dev/sda bs=512 count=1` from any
  Linux that can see the disk.
