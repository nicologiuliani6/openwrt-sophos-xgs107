# x86 ↔ NPU link: Ethernet over the PCIe endpoint (vNTB)

Status 2026-09-19: **works**. The x86 OpenWrt gets `ntb0`, bridged to the
NPU's LAN; the x86 is `192.168.1.2`, the NPU `192.168.1.1` (DHCP and NAT).
Ping 1.3 ms, x86 has Internet through the NPU, its LuCI and SSH are
reachable from any LAN port. The Sophos-proprietary `mv_pcinet` path is not
used at all.

## How it is built

- The CN9130 PCIe controller (`cp0_pcie0`, DesignWare, wired to the x86) is
  left in **endpoint mode** with the link up by the stock U-Boot. The DTS
  turns the node into `snps,dw-pcie-ep` (`dbi` `0xf2600000`, `dbi2`
  `0xf2604000`, `addr_space` `0x80_0000_0000` 256 MB; the stock DT used the
  same registers and a 32 GB host window).
- `pci-epf-vntb` (configfs, `openwrt/files-npu/etc/init.d/vntb`) presents
  `1957:0809` to the host with ctrl=BAR0, doorbell=BAR2, MW1=BAR4 (the BAR
  map that `ntb_hw_epf` uses for that ID).
- Host: `ntb`, `ntb_transport`, `ntb_hw_epf`, `ntb_netdev` (package
  `kmod-ntb-epf`). NPU: `ntb_transport`, `ntb_netdev` as modules
  (`kmod-ntb-netdev`; built in they initialise before the bus exists).
  A one-line patch names the interface `ntb%d`.
- The x86 runs `/usr/sbin/ntb-link-wait` (procd): it rescans PCI until the NPU's
  function shows up and rebuilds the link if `ntb0` has no carrier for a minute.
  So the boot order of the two sides does not matter.

## What was wrong (three separate things, all needed)

1. **BAR memory must be 1 MB aligned.** The BAR-match inbound iATU on this
   core ignores the low 20 bits of the target (the BARs are 1 MB). The EPF
   core allocates a 2 KB control BAR with page alignment, so the host
   read/wrote up to 1 MB below the real buffer: garbage `MW count`,
   commands never seen. Fix: `.align = SZ_1M` in the plat driver's endpoint
   features (`patches/951`). Also disable the iATU windows U-Boot leaves
   enabled at endpoint init.
   How it was found: dump of the iATU registers (`ib0 … lt 02b20000`), and
   decompiling the stock `armada_pcie_ep_bar_map` (same registers, viewport
   mode) to see that nothing exotic is needed.
2. **Cache coherency.** With `dma-coherent` on the endpoint node the host
   read stale DRAM (the PCIe master does not snoop, AxDOMAIN is
   non-shareable). The node has `dma-coherent` deleted: uncached buffers.
3. **MSI vs MSI-X.** DesignWare always advertises MSI-X; `ntb_hw_epf` asked for
   it, the vNTB function raises MSI, the NPU wrote to a zero MSI-X table and
   AMD-Vi logged `IO_PAGE_FAULT address=0x0`. Host patch: prefer MSI
   (`patches/953`).

Other lessons: `dd of=/dev/mem` on the x86 into a BAR is a fine probe;
`ntb_transport`/`ntb_netdev` built in (`=y`) register before the bus and
silently do nothing; an OpenWrt full build turns `build_dir/.../Image` into the
**initramfs** kernel, deploy only the Image from `target/linux/compile`.

## Caveats

- Resetting the NPU while the x86 has the NTB bound reboots the x86 (the
  PCIe link disappears under it). It comes back on its own and re-links.
- The NPU firmware side of the link is 1 MB BARs and one queue pair: ~ a few
  hundred Mbit/s is expected, not measured yet.
- No root password on either side by choice (testing). SSH key of the
  builder is installed on the x86.

## Getting files onto the x86 before there was a network

`scripts/97-console-put.py LOCAL /tmp/REMOTE` copies a file over the x86's
serial console (no base64/stty on the busybox): 110-byte chunks written with
`echo -ne '\x..'`, each checked with `md5sum`, ~13 KB/s. Used to bring the
first four modules over; everything after that went over ssh.
