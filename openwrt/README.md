# OpenWrt support for the XGS 107w NPU

- `0001-mvebu-add-Sophos-XGS-107w-NPU.patch`: against OpenWrt `main`
  (b6ba4e9, kernel 6.18). Adds the device `sophos_xgs107w` to
  `mvebu/cortexa72`: the DTS, the image profile, `board.d` network (panel
  port 2 = WAN, other ports + SFP = LAN, MACs from the U-Boot env) and the
  U-Boot env location. It also carries the kernel patch
  `950-net-dsa-mv88e6xxx-continue-without-PTP-clock.patch` (same as
  `../patches/`), without which the 88E6193X fails to probe.
- `diffconfig`: the build configuration (initramfs + ext4 rootfs, LuCI,
  iperf3, ethtool, uboot-envtools).

Build:

```sh
git clone https://github.com/openwrt/openwrt && cd openwrt
git checkout b6ba4e9 && git apply ../openwrt/0001-mvebu-add-Sophos-XGS-107w-NPU.patch
./scripts/feeds update -a && ./scripts/feeds install -a
cp ../openwrt/diffconfig .config && make defconfig && make -j$(nproc)
```

Outputs used:
- `bin/targets/mvebu/cortexa72/*-initramfs-kernel.bin`: RAM boot via
  kexec (`scripts/60-npu-kexec-openwrt.cmds`);
- the eMMC slot image, from `scripts/80-mk-emmc-slot.sh <tree> <out>`.

Install: [../docs/openwrt-install.md](../docs/openwrt-install.md).
