# OpenWrt for the Sophos XGS 107w

OpenWrt on both computers inside the Sophos XGS 87/107 desktop firewall: the
Marvell CN9130 network processor runs the router (all 8 gigabit ports, SFP,
LuCI), the AMD x86 runs the Wi-Fi access point and the USB port. A virtual Ethernet over
PCIe joins them. No Sophos code is used.

## Install

You need the appliance, a PC on the same network, and the x86 console
(micro-USB). Back up the stock system first ([docs/backup.md](docs/backup.md)),
open the SFOS advanced shell (login `admin`, menu 5, then 3), then on the PC:

```sh
git clone https://github.com/nicologiuliani6/openwrt-sophos-xgs107.git
cd openwrt-sophos-xgs107
./install.sh --serial
```

It builds the images, serves them, and runs both installers on the appliance
(`./install.sh` without `--serial` prints the two commands to paste instead).
Then power-cycle the appliance and open <http://192.168.1.1> (router) and
<http://192.168.1.2> (x86, Wi-Fi). Set a root password. Details:
[docs/install.md](docs/install.md).

The stock Sophos system stays bootable on the NPU as a fallback. After the
install, never let SFOS boot on the x86: it erases the OpenWrt root.

## Not working or untested

- **USB**: the front port is the x86's (a USB drive is detected and readable); the NPU's own xHCI controllers are enabled but nothing is wired to them that we found. Speed and hot-plug not measured.
- **Port LEDs**: wired in the device tree, polarity and colours are guesses.
- **SFP cage**: untested (no module).
- **Wi-Fi**: the access point is off until you set an SSID and key; throughput
  not measured.
- **Routing performance** and LAN-to-LAN forwarding: not measured.
- **Resetting the NPU reboots the x86** (it comes back and re-links by itself).
- **`./install.sh --serial`** has not been run end to end on hardware.

## Documentation

[Install](docs/install.md) · [Backup](docs/backup.md) · [Usage](docs/usage.md) ·
[Build](docs/build.md) · [Recovery](docs/recovery.md) ·
[Troubleshooting](docs/troubleshooting.md) ·
[Architecture](docs/architecture.md) · [Hardware](docs/hardware.md) ·
[NPU–x86 link](docs/npu-x86-link.md) · [Upstreaming](docs/upstreaming.md)

## Who did what

**Human (owner):** obtained the hardware; all physical work (opening the
unit, wiring the serial adapters, cabling, power cycles, reading LEDs and
ports); reset the SFOS password; chose the goals (drop SFOS, keep stock as
fallback, x86 on OpenWrt, upstream the patches); authorised every write to
the device; reviews and sends the upstream patches.

**AI (Claude):** everything else: reading the hardware from a live unit,
reverse engineering of the stock system, the device tree, kernel patches,
init and installer scripts, build system, the PCIe endpoint link, the
documentation, and the patch review. The AI ran the commands on the device
under the owner's standing permission.

## Code provenance

| | Status |
|---|---|
| Unmodified upstream code: Linux mainline drivers (`mv88e6xxx`, `mvpp2`, DesignWare endpoint, `pci-epf-vntb`, `ntb_*`, `ath10k`), OpenWrt, LuCI, stock U-Boot | widely used and tested by others |
| Written by the AI and run on the one reference unit, not in production: the device tree, kernel patches 950–954, NPU/x86 link scripts, `install-x86.sh` and `install-npu.sh` (earlier versions of them ran; the current rewrite was not re-run), `x86-mbr.py`, console tools | works on that unit, never in the field |
| Written by the AI, never run on hardware: `install.sh`, `backup-stock.sh`, `--serial` mode, the from-scratch `build/build.sh` pipeline (being verified), USB and LED configuration | untested |
| Upstream patches (`upstream/`) | compiled and schema-checked; the DTS boots on the unit; not yet reviewed by maintainers |

Expect bugs. Do not use it for anything you cannot re-flash.

## AI usage

Model: Claude (Opus 5 for the first part, then Sonnet 5), through Claude Code,
over a multi-day session plus several helper agents. Token count and cost were
not recorded by the tool: the session processed on the order of tens of
millions of tokens, mostly cached context re-reads (an estimate, not a
measurement). Exact figures: the owner's Claude usage page.
