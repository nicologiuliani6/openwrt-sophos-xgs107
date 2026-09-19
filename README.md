# OpenWrt for the Sophos XGS 107w

OpenWrt on both computers inside the Sophos XGS 87/107 desktop firewall: the
Marvell CN9130 network processor runs the router (all 8 gigabit ports, SFP,
USB, LuCI), the AMD x86 runs the Wi-Fi access point. A virtual Ethernet over
PCIe joins them. No Sophos code is used.

## Install

You need the appliance, a PC on the same network, and the x86 console
(micro-USB). Back up the stock system first ([docs/backup.md](docs/backup.md)),
open the SFOS advanced shell (login `admin`, menu 5, then 3), then on the PC:

```sh
git clone https://github.com/nicologiuliani6/sophos-xgs107w-prestera.git
cd sophos-xgs107w-prestera
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

- **USB**: controllers enumerate; never tried with a device.
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
