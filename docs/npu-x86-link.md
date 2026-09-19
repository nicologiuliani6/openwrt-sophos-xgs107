# NPU ↔ x86 link: Ethernet over the PCIe endpoint

The x86 has no network interface of its own. Under SFOS it reaches the
switch through Sophos's proprietary host drivers; here it gets an ordinary
virtual Ethernet, `ntb0`, over the PCIe connection to the NPU, using only
mainline Linux code plus five small patches.

Result: `ntb0` on both sides, bridged into the NPU's LAN; the x86 is
`192.168.1.2`, the NPU `192.168.1.1`. Ping 1.3 ms; the x86 reaches the
Internet through the NPU; its LuCI and SSH are reachable from any LAN port.

## How it is built

- The stock U-Boot leaves the CN9130's PCIe controller (`cp0_pcie0`,
  DesignWare with a Marvell wrapper) in **endpoint mode**, link up. The
  device tree turns that node into `snps,dw-pcie-ep`: `dbi` `0xf2600000`,
  `dbi2` `0xf2604000`, an outbound window `addr_space` at `0x80_0000_0000`
  (256 MB; the stock DT reserved 32 GB there), the `dma-coherent` property
  removed.
- `/etc/init.d/vntb` on the NPU (`openwrt/npu/base-files/`) builds a
  `pci-epf-vntb` function through configfs. It presents `1957:0809` to the
  host with control = BAR0, doorbell = BAR2, memory window 1 = BAR4 (the map
  `ntb_hw_epf` uses for that ID), 4 doorbells, 128 scratchpads, 1 MiB window.
- The x86 loads `ntb`, `ntb_hw_epf`, `ntb_transport`, `ntb_netdev` (package
  `kmod-ntb-epf`); the NPU has the endpoint function built in and
  `ntb_transport` + `ntb_netdev` as modules (`kmod-ntb-netdev`: built into the
  kernel they initialise before the bus exists and silently do nothing).
  `ntb_transport` runs with `transport_mtu=2048` on both sides (see below).
- `/usr/sbin/ntb-link-wait` (procd service `ntb-link`) on the x86 rescans PCI
  until the NPU's function shows up and rebuilds the link if `ntb0` stays
  without carrier for a minute, so the boot order of the two modules does not
  matter.

## Why it needs patches

1. **BAR memory must be 1 MiB aligned.** The BAR-match inbound iATU on this
   core ignores the low 20 bits of the target address; the BARs are 1 MiB.
   The endpoint framework allocates the 2 KiB control area with page
   alignment, so the host read and wrote up to 1 MiB below the real buffer:
   nonsense `MW count`, commands that were never seen. Fix
   (`951-PCI-dwc-plat-ep-1M-BAR-align`): `.align = SZ_1M` in the endpoint
   features, and disable the iATU windows U-Boot left enabled. Found by
   dumping the iATU registers and by disassembling the stock kernel's
   `armada_pcie_ep_bar_map` (the same standard registers).
2. **No cache coherency.** With `dma-coherent` the host read stale DRAM: the
   PCIe master here does not snoop the CPU caches (its AxDOMAIN is
   non-shareable). Without the property the buffers are uncached and both
   directions are coherent.
3. **MSI versus MSI-X.** The DesignWare core always advertises MSI-X;
   `ntb_hw_epf` preferred it, but the function raises MSI, so the NPU wrote
   through an empty MSI-X table and the x86's IOMMU logged
   `IO_PAGE_FAULT address=0x0`. Fix (`953-ntb-hw-epf-prefer-msi`, host).
4. **Throughput.** Doorbells from the host are found by polling the control
   area (there is no interrupt), every 5 ms rounded up to a whole tick
   (10 ms at HZ=100): `954` polls every 1 ms and the kernel runs HZ=1000. And
   with the default 64 KiB transport frames the 1 MiB window has 15 slots,
   so every small packet waits for a round trip: `transport_mtu=2048` on both
   sides gives 511 slots. Measured with iperf3: **630 Mbit/s NPU→x86,
   1.7 Gbit/s x86→NPU** (12 and 6 Mbit/s before).

## Behaviour to know

- Resetting or losing the NPU while the x86 has the link bound reboots the
  x86 (the PCIe endpoint disappears under an active driver). It comes back
  by itself and re-links.
- The interface MTU is 2022 (frame size minus headers); bridged with the
  1500-byte LAN it is effectively 1500.

## Copying files to the x86 without a network

`tools/console-put.py LOCAL /tmp/REMOTE` copies a file over the x86's serial
console (its busybox has no `base64` or `stty`): 48-byte chunks written
with `echo -ne '\x..'`, each verified with `md5sum` and resent if wrong,
about 1.5 KB/s. Useful for bootstrapping; with the link up, fetch files over HTTP with `wget`.
