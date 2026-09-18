# kexec test cycle for the NPU (from the SFOS x86 shell)

Boots a kernel on the CN9130 from RAM, from the stock NPU Linux, with no
eMMC/SPI/env writes. Run from the SFOS advanced shell (console menu 5 → 3).

1. PC: `cd ~/src/xgs-build/stage && python3 -m http.server 8001` (Image,
   xgs.dtb, initramfs.cpio.gz, kexec, SHA256SUMS).
2. `sg dialout -c 'python3 scripts/40-console-send.py --idle 20' < scripts/60-npu-kexec.cmds`
3. NPU console lands in SFOS `/tmp/npu.log` (captured from x86 `/dev/ttyS2`).
4. Back to stock: SysRq-b over ttyS2 (BREAK, then `b`). **SFOS on the x86
   crashes** when the NPU drops off PCIe (`mv_giu_drv` BUG in kfree). It
   reboots on its own, and the whole appliance comes back stock in about
   4 minutes. Read `/tmp/npu.log` *before* this step: it is on tmpfs.
