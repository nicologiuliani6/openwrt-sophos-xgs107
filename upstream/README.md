# Upstream submission for Linux (draft, NOT sent)

Author of all patches: `Nicolo Giuliani <nicologiuliani6@studio.unibo.it>`.
Base: Linux v6.18.52 files. **Before sending, rebase on the current
subsystem tree** (see below); the driver code in particular may have moved.

Two independent submissions, because maintainers and trees differ:

## A. Board support (3 patches) → Marvell mvebu maintainers, arm-soc

| Patch | What |
|---|---|
| `0001` | `dt-bindings: vendor-prefixes: Add Sophos` |
| `0002` | `dt-bindings: arm: marvell: Add Sophos XGS 107w NPU` |
| `0003` | `arm64: dts: marvell: Add Sophos XGS 107w NPU board` |

Checks done on the tree with the series applied:
`checkpatch.pl --strict` (only the missing Signed-off-by, and the generic
"does MAINTAINERS need updating?" for a new board file),
`make dt_binding_check` (clean), `make CHECK_DTBS=y
marvell/cn9130-sophos-xgs107w.dtb` (no warning on this board's nodes; the
remaining ones come from `armada-ap80x`/`cp11x.dtsi` and appear on every
CN913x board, e.g. `cn9130-crb-A`).

Tested on hardware: the board boots this DT (Linux 6.18.52, later also
OpenWrt), eMMC, SPI NOR read-back identical to the U-Boot dump, `mvpp2` at
10 Gb/s to the switch, 88E6193X with 8 DSA ports, 941 Mbit/s iperf3
through a front port. **Not tested:** the SFP cage (no module), the port
LED GPIO expander.

Recipients (from `scripts/get_maintainer.pl`):

```
To: Gregory Clement <gregory.clement@bootlin.com>,
    Andrew Lunn <andrew@lunn.ch>,
    Sebastian Hesselbarth <sebastian.hesselbarth@gmail.com>,
    Rob Herring <robh@kernel.org>,
    Krzysztof Kozlowski <krzk+dt@kernel.org>,
    Conor Dooley <conor+dt@kernel.org>
Cc: linux-arm-kernel@lists.infradead.org, devicetree@vger.kernel.org,
    linux-kernel@vger.kernel.org
```

Cover letter text (subject `[PATCH 0/3] arm64: dts: marvell: Add Sophos XGS 107w NPU`):

> The Sophos XGS 87/107 desktop firewalls contain an AMD x86 host and a
> separate network processing unit: an Armada CN9130 with its own eMMC and
> SPI NOR, connected to an 88E6193X switch over its 10G mvpp2 port. The
> CN9130 runs its own Linux and is normally driven from the host over PCIe.
>
> This adds the compatible and a devicetree for the NPU as a standalone
> system booting from its own eMMC. Tested on hardware with the stock
> U-Boot: eMMC, SPI NOR, all eight front ports through DSA, routing at
> line rate. SFP and the LED expander are described but untested.
>
> The switch reset GPIO is deliberately not used as reset-gpios: the
> 88E6193X needs about two seconds after reset, which mv88e6xxx does not
> wait for; the boot loader resets it instead.

## B. Driver fix (1 patch) → netdev

`0004 net: dsa: mv88e6xxx: continue without PTP if the TAI clock is unusable`

Recipients: Andrew Lunn, Vladimir Oltean, David S. Miller, Eric Dumazet,
Jakub Kicinski, Paolo Abeni, Richard Cochran; lists `netdev@vger.kernel.org`,
`linux-kernel@vger.kernel.org`. Subject prefix `[PATCH net-next]`.

Please expect review to ask *why* the TAI period register reads 0 on this
board (never configured by the boot loader?). If a better fix is to
program the TAI clock, this patch can be dropped in favour of that. The
patch is small and makes the switch usable meanwhile.

## Steps to finish (you, since it is your certification and identity)

```sh
git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/netdev/net-next.git
cd net-next && git checkout -b xgs
git am ../upstream/0004-*.patch          # adjust if it no longer applies
git rebase --signoff HEAD~1              # adds Signed-off-by: you (DCO)
scripts/checkpatch.pl --strict -g HEAD
git send-email --to=netdev@vger.kernel.org --cc=... HEAD~1
```

For series A use the arm-soc / mvebu tree (`git://git.kernel.org/pub/scm/linux/kernel/git/gclement/mvebu.git`)
the same way. `Signed-off-by` is intentionally missing from the patches:
it is a personal certification of the Developer Certificate of Origin.
The patches carry an `Assisted-by:` trailer for the AI models that helped
write them, as the kernel's process documentation asks.
