# OpenWrt on the Sophos XGS 107w

Run OpenWrt on **both** computers inside the Sophos XGS 107w (also the 87)
desktop firewall, with all eight gigabit ports, the SFP cage, USB and the
Wi-Fi card working, instead of Sophos's SFOS.

The box is an AMD x86 host plus a separate Marvell CN9130 network processor
with an 88E6193X switch behind it. Sophos's firmware drives the ports through
proprietary kernel modules, which is why a stock Linux or OpenWrt on the x86
sees no ports. Here the CN9130 runs OpenWrt as the router and the x86 runs
OpenWrt as the Wi-Fi access point, joined by a virtual Ethernet over PCIe.
See [docs/architecture.md](docs/architecture.md).

## Status

| | |
|---|---|
| 8 RJ45 ports, DSA, hardware switching | works, 941 Mbit/s through a port |
| WAN on panel port 2 (DHCP), LAN bridge, NAT, LuCI | works |
| x86 OpenWrt from the internal disk, Wi-Fi radio (QCA988x) | works; AP off until you set an SSID and key |
| NPU ↔ x86 link (virtual Ethernet, `ntb0`) | works, 630 Mbit/s and 1.7 Gbit/s |
| USB (NPU) | controllers enumerate, **not tried with a device** |
| Port LEDs | wired in the DT, polarity **unconfirmed** |
| SFP cage (F1) | described, **untested** (no module) |
| Stock Sophos on the NPU | kept as U-Boot fallback (slot p3) |
| Upstream | 4 Linux patches ready, not sent ([docs/upstreaming.md](docs/upstreaming.md)) |

Tested on one unit: XGS 107w, SFOS 19.5.4 MR-4, board rev 1.40.

## Install

You need the appliance, a PC on the same network, and the x86 console (the
micro-USB port). Read [docs/install.md](docs/install.md), take the
[backup](docs/backup.md), open the SFOS advanced shell, then:

```sh
git clone https://github.com/nicologiuliani6/sophos-xgs107w-prestera.git && cd sophos-xgs107w-prestera
./install.sh --serial        # or ./install.sh and paste the two lines it prints
```

It builds (or reuses) the images, serves them, and runs the two installers
on the appliance; afterwards power-cycle it. Both modules then boot OpenWrt;
open <http://192.168.1.1> (router) and <http://192.168.1.2> (x86, Wi-Fi).
No root password is set: set one.

## Documentation

| | |
|---|---|
| [docs/install.md](docs/install.md) | full procedure, what is written, how to undo |
| [docs/backup.md](docs/backup.md) | backing up and restoring the stock system |
| [docs/usage.md](docs/usage.md) | network, Wi-Fi, USB, LEDs, limits |
| [docs/build.md](docs/build.md) | building the images, the patches |
| [docs/recovery.md](docs/recovery.md) | consoles, back to stock, when something breaks |
| [docs/troubleshooting.md](docs/troubleshooting.md) | symptoms and fixes |
| [docs/architecture.md](docs/architecture.md), [docs/hardware.md](docs/hardware.md), [docs/npu-x86-link.md](docs/npu-x86-link.md) | how it works |
| [docs/upstreaming.md](docs/upstreaming.md) | Linux patches |
| [docs/reference/](docs/reference/) | Sophos firmware, prior art, dump manifest |
| [docs/history/](docs/history/) | the bring-up log |

## Repository

```
install.sh            the one-command installer (runs on the PC)
install/              scripts that run on the appliance, U-Boot env, x86 MBR tool
build/                build.sh, mk-emmc-slot.sh, per-target configs
openwrt/              patches, device tree, base-files, x86 overlay, apply.sh
tools/                serial console helpers, GRUB driver, dump receiver
upstream/             Linux patches for mainline (not sent)
docs/
```

## Safety

The SPI U-Boot is never written. The NPU installs into eMMC slot p1 and the
stock slots stay bootable. On the x86, **never let SFOS boot again** after the
install: it re-creates its swap over the OpenWrt root. Details:
[docs/recovery.md](docs/recovery.md).

## Licence

Patches to Linux and OpenWrt follow their projects' licences (GPL-2.0).
Nothing from Sophos or Marvell is included; backups of a device stay in
`dumps/`, which git ignores.
