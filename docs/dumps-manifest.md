# Dumps manifest

Binaries live in `dumps/` (gitignored: proprietary Sophos/Marvell content).
Only this index is committed. Taken 2026-09-18 from a stock XGS 107w
(SFOS 19.5.4 MR-4) via `scripts/50-dump-receiver.py`, streamed with
`xgs-ssh.sh "cat <dev>" | curl -T -`. See [bench-log.md](bench-log.md) §8.

**Verification:** each NPU block device was hashed on the NPU itself
(`sha256sum`) and the result compared with the hash of the received file.
All match. `npu/sha256-on-device.txt` holds the device-side eMMC hashes.

## NPU (CN9130)

| File | Source | Size | sha256 | Device hash match |
|---|---|---|---|---|
| `dumps/npu/mtd0-uboot.bin` | /dev/mtd0 (SPI u-boot) | 4128768 | `fe13a2a3d4240bcef568bcef41b9270a95bdf01e785ea1e3d055a43f031c2473` | ✅ |
| `dumps/npu/mtd1-uboot-env.bin` | /dev/mtd1 (u-boot env) | 65536 | `3325e15d004e7f670d2a630d65220a307ecd7e2bd6794eb77c061295da7d6874` | ✅ |
| `dumps/npu/mmcblk0boot0.bin` | /dev/mmcblk0boot0 (all zero) | 4194304 | `bb9f8df61474d25e71fa00722318cd387396ca1736605e1248821cc0de3d3af8` | ✅ |
| `dumps/npu/mmcblk0boot1.bin` | /dev/mmcblk0boot1 (all zero) | 4194304 | `bb9f8df61474d25e71fa00722318cd387396ca1736605e1248821cc0de3d3af8` | ✅ |
| `dumps/npu/running.dtb` | /sys/firmware/fdt | 32768 | `9bb8e5267ee18bd10964675146149b9e6b0547cf169963e9bf882adcdbed357a` | ✅ |
| `dumps/npu/mmcblk0-full.img` | /dev/mmcblk0 (whole eMMC) | 7818182656 | `86a76be03caed702ba859ac2d2befee4350fab9a116bfb4c9e0bfaa91358e524` | ✅ |
| `dumps/npu/sha256-on-device.txt` | text capture | 403 | `f34925c9d32ef908f6164cccfcbaa68c212a003214583d1208bffeb3fc66d2eb` | — |
| `dumps/npu/sysinfo.txt` | text capture | 105153 | `acecfa95e1a07abef375616559c4300b3f2e7060a8f9703dde3ac077077701f1` | — |

eMMC partitions (MBR), hashes identical on the device and in the image:

| Part | Start sector | Sectors | Size | sha256 |
|---|---|---|---|---|
| p1 | 2048 | 1024000 | 500 MiB | `351926cc587dd680f509969944f5bb50597befaa1e6eab7614389ae963a475de` |
| p2 | 1026048 | 3121152 | 1524 MiB | `2941cdd6e861d07b87bf3415d12570ae4105f4b95b618bfea0fa5ddf2417b043` |
| p3 | 4147200 | 3121152 | 1524 MiB | `271a8d1a9f3f3d2e417b73d2d7a6f2ec18488232b4c6aeb7111d94dc990ea769` |
| p4 | 7268352 | 204800 | 100 MiB | `f47bd93facc425825e56c6a73db55ade8101c5fee42da3d62340594b7d333261` |
| free | 7473152 | 7796736 | ~3.7 GiB | unallocated |

## x86 (SFOS)

| File | Contents | Size | sha256 |
|---|---|---|---|
| `dumps/x86/sfos-npu-tooling.tar.gz` | /bin/xgs-*, /scripts/npu*, xgs-healthmond, /lib/modules/4.14.277/extra, opkg info | 1140336 | `47493f0f0266c9daeff3f278bd4ad03ae446abb2cd427902cf686330b0d6fdce` |
| `dumps/x86/xgs-platform.txt` | xgs-platform | 4158 | `318b8c98a2de83b4fb297577527812457d23a2fffb4fd7cc65e272fa1a832af1` |
| `dumps/x86/lspci-vvv.txt` | lspci -vvv -nn | 26649 | `c0b3a10478c4480097e64e8c53fdc589312ee5159413d1e6c07498c4d738af1d` |
| `dumps/x86/dmesg.txt` | dmesg | 67754 | `dfac3160fc2b2b12a59dfc0842a0da343c716bcc682c1ac7af9b841cd12a81f0` |
| `dumps/x86/sysinfo.txt` | dmidecode, /proc, lsmod, ip | 44151 | `98a240636e0d6bf1640e3d1906a930e8ba117bcaf2d61a54960d77c417ae122a` |
| `dumps/x86/npu-image-candidates.txt` | find for NPU images on x86 — none found | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |

SFOS's own NPU images, from `/sdisk/npu/` on the x86 disk. These are the
images SFOS reinstalls onto the NPU from; see `npu_host_validation.sh`.
Verified by md5 on the x86 (no `sha256sum` there), both match:

| File | Size | sha256 (PC) | md5 (x86 = PC) |
|---|---|---|---|
| `dumps/x86/sdisk-npu/npu_slot1_19_5_3_652.img` | 624132096 | `3ad66e6be471bdadd81b3145c4a66f71099801b5ea3ff3913a4f027c04ec3ecf` | `6fb8a377041e26910869bf3c16bf6dd0` |
| `dumps/x86/sdisk-npu/npu_slot2_19_5_4_718.img` | 589017088 | `92afd57b2aa77a076d5643c1b2ba39cb8367d1055eb94bc651b8dc5a4aa432ba` | `51f3b4a67eb3ca52334de672a8f661b3` |

Derived, local only: `dumps/npu/parts/p{1..4}.img` (partitions cut from the
full image) and `dumps/x86/tooling/` (unpacked tarball).

## Restore

- **eMMC:** write `mmcblk0-full.img` back to `/dev/mmcblk0`, or a single
  `parts/pN.img` to `/dev/mmcblk0pN`, from a running NPU Linux (stock or
  ours).
- **SPI u-boot:** `mtd0-uboot.bin` is a byte-exact copy of `/dev/mtd0`. The
  plan never writes `mtd0`; this copy is the last-resort backup.
  `xgsdt1-boot.img` inside p2/p3 `/boot` is Sophos's own u-boot image, used
  by `xgs-npu-uboot-update.sh`.
