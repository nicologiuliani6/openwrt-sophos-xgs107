# OpenWrt changes

`build/build.sh` applies all of this with `openwrt/apply.sh`; see
[../docs/build.md](../docs/build.md).

```
patches/          edits to existing OpenWrt files (git format-patch series)
npu/dts/          device tree of the NPU (sophos_xgs107w, mvebu/cortexa72)
npu/base-files/   NPU root filesystem additions: vNTB init, defaults, LuCI page
npu/kernel-patches/  Linux patches for the NPU (950, 951, 952, 954)
x86/kernel-patches/  Linux patches for the x86 build (952, 953)
x86/files/        x86 root filesystem overlay: network defaults, ntb link supervisor
apply.sh          openwrt/apply.sh <openwrt-tree> <npu|x86>
```
