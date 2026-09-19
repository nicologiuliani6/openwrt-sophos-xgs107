# Upstream submission

The board is not in mainline Linux or OpenWrt yet. Four Linux patches are
ready in `upstream/`, against Linux v6.18.52 (rebase on the current
subsystem tree before sending):

| Patch | What | Send to |
|---|---|---|
| `0001` | `dt-bindings: vendor-prefixes: Add Sophos` | Marvell mvebu / arm-soc, devicetree list |
| `0002` | `dt-bindings: arm: marvell: Add Sophos XGS 107w NPU` | same |
| `0003` | `arm64: dts: marvell: Add Sophos XGS 107w NPU board` | same |
| `0004` | `net: dsa: mv88e6xxx: continue without PTP if the TAI clock is unusable` | netdev |

`0001`–`0003` are one series (`[PATCH 0/3]`); `0004` is separate
(`[PATCH net-next]`). Get the recipients with `scripts/get_maintainer.pl`
on the rebased tree.

Checks done: `checkpatch.pl --strict`, `make dt_binding_check` (clean),
`make CHECK_DTBS=y marvell/cn9130-sophos-xgs107w.dtb` (no warning on this
board's nodes). Tested on hardware: boot, eMMC, SPI NOR, `mvpp2` at 10 Gb/s,
the 88E6193X with eight DSA ports, 941 Mbit/s through a front port. Not
tested: the SFP cage and the port LEDs.

The DT patch describes the NPU as a standalone system. The PCIe endpoint,
USB and LED nodes in `openwrt/npu/dts/cn9130-sophos-xgs107w.dts` are added
in the OpenWrt DTS and are not part of the upstream patch yet (the endpoint
needs the patches in `openwrt/npu/kernel-patches/` first).

The switch's reset GPIO is deliberately not `reset-gpios`: the 88E6193X
needs about two seconds after reset, longer than `mv88e6xxx` waits, so the
boot loader does it.

For `0004`, a reviewer will reasonably ask why the TAI period register
reads 0 on this board (never configured by the boot loader?). If programming
the TAI clock is preferred, drop the patch in favour of that.

## Sending

```sh
git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/netdev/net-next.git
cd net-next && git am ../upstream/0004-*.patch      # adjust if it no longer applies
scripts/checkpatch.pl --strict -g HEAD
git send-email --to=netdev@vger.kernel.org --cc=... HEAD~1
```

For `0001`–`0003` use the mvebu/arm-soc tree the same way.
