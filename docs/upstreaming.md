# Upstream submission

The board is not in mainline Linux or OpenWrt yet. The Linux patches are in
`upstream/`:

| Patch | What | Tree |
|---|---|---|
| `0001` | `dt-bindings: vendor-prefixes: Add Sophos` | Marvell mvebu (`mvebu/dt`) |
| `0002` | `dt-bindings: arm: marvell: Add Sophos XGS 107w NPU` | same |
| `0003` | `arm64: dts: marvell: Add Sophos XGS 107w NPU board` | same |
| `0004` | `net: dsa: mv88e6xxx`: continue without PTP if the TAI period is invalid | `net` (a fix, with a `Fixes:` tag) |

`0001`–`0003` are one series with the cover letter `0000-cover-letter.txt`;
`0004` is sent on its own.

The DTS in `0003` describes the NPU as a standalone system (UART, eMMC, SPI
NOR, GPIO expander, SFP, the switch with eight DSA ports). The PCIe endpoint,
USB and LED nodes of `openwrt/npu/dts/cn9130-sophos-xgs107w.dts` are OpenWrt
only.

The switch's reset line (CP GPIO2 pin 17) is described with `reset-gpios`.

## Checks

`dt_binding_check` (clean), `CHECK_DTBS=y` on the board's DTB (only warnings
shared with other CN913x boards), `checkpatch.pl --strict --codespell`
(clean; one inherent MAINTAINERS notice on the DTS), the driver builds with
`W=1` with PTP on and off. The trimmed DTS boots the reference unit: eMMC,
the 88E6193X with eight ports and the SFP node, 10 Gb/s to the switch,
936 Mbit/s through a port. The SFP cage and LEDs are untested.

## Sending with b4

```sh
pip install b4 patatt
patatt genkey                                   # then add the printed [patatt] block to ~/.gitconfig
git config --global b4.send-endpoint-web https://lkml.kernel.org/_b4_submit
b4 send --web-auth-new                          # confirm the emailed challenge:
b4 send --web-auth-verify <challenge>           #   done once
```

DT series, in a clone of the mvebu tree:

```sh
git checkout -b sophos-npu origin/mvebu/dt
git am -3 upstream/000[123]-*.patch
b4 prep -e origin/mvebu/dt
b4 prep --edit-cover                            # paste upstream/0000-cover-letter.txt
b4 prep --auto-to-cc
b4 send -o /tmp/out                             # writes the emails, sends nothing
b4 send --reflect                               # sends only to yourself
b4 send
```

Netdev patch, in a clone of the `net` tree:

```sh
git checkout -b mv88e6xxx-ptp origin/main
git am -3 upstream/0004-*.patch
b4 prep -e origin/main
b4 prep --set-prefixes net
b4 prep --edit-cover
b4 prep --auto-to-cc
b4 send -o /tmp/out && b4 send --reflect && b4 send
```

Rebase on the current tip before sending; `git am -3` reports any drift.
