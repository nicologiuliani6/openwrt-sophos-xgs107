# Using the appliance

## Network

| | |
|---|---|
| Panel port 2 | **WAN**, DHCP client |
| Panel ports 1, 3–8 and the SFP (F1) | **LAN**, one bridge `br-lan` on the NPU: `192.168.1.1/24`, DHCP server on, NAT to the WAN |
| x86 module | `192.168.1.2`, on the same LAN through the internal link (`ntb0`); default gateway and DNS are the NPU |
| Wi-Fi clients | bridged into the same LAN, addresses from the NPU's DHCP |

Web interfaces (LuCI), user `root`, **no password until you set one**
(System → Administration):

- <http://192.168.1.1> – the router: interfaces, firewall, DHCP, USB, LEDs.
  *Network → Wi-Fi / x86 module* links to the x86's wireless page.
- <http://192.168.1.2> – the x86: **Wi-Fi**, and its own status. SSH is on
  both. Under *Network → Wireless* the radio (`radio0`, QCA988x, 5 GHz
  channel 36, VHT80, country IT) is present and up.

Neither system has a root password until you set one.

## Wi-Fi

The access point is defined but **disabled and open**, on purpose. On
`http://192.168.1.2` → Network → Wireless → the radio → *Edit* the
interface: set the SSID, *Encryption* (WPA2-PSK or WPA3-SAE), the key, and
*Enable*. Save & Apply. The access point is bridged to `lan`, so clients get
their address from the NPU and reach every port. Set the country code that
matches where you are (it defaults to IT).

Or, from a shell on the x86:

```sh
uci set wireless.default_radio0.ssid='MyNetwork'
uci set wireless.default_radio0.encryption='sae-mixed'
uci set wireless.default_radio0.key='a long passphrase'
uci set wireless.default_radio0.disabled='0'
uci set wireless.radio0.country='DE'
uci commit wireless && wifi reload
```

## USB

The USB port belongs to the NPU (two xHCI controllers are enabled, VBUS on).
Storage, serial adapters and Ethernet dongles use the usual OpenWrt
packages (`kmod-usb-storage`, `block-mount` are preinstalled); mount points
are set in *System → Mount Points* on `192.168.1.1`. **Status: the
controllers enumerate; not yet tried with a device.**

## LEDs

Each RJ45 port has two LEDs driven by a GPIO expander: `green:lan-N` and
`amber:lan-N` in *System → LED Configuration*. The green ones are set to
show link and activity of `pN`. The pin polarity and colours are a guess
from the stock tables; if the LEDs look inverted or dark, change the
trigger there, or `active-low` in the DTS
(`openwrt/npu/dts/cn9130-sophos-xgs107w.dts`) and rebuild.

## Performance (measured)

| | |
|---|---|
| PC ↔ NPU through a front port | 941 Mbit/s line rate |
| NPU ↔ x86 internal link | 630 Mbit/s (NPU→x86), 1.7 Gbit/s (x86→NPU) |
| Wi-Fi | not measured (one 5 GHz radio, ath10k) |

Forwarding between two LAN ports and routed throughput with a wired host on
the WAN side have not been measured. TCP from the NPU itself to a gigabit
host shows retransmissions: the 10G link into the switch outruns its
1G ports; pause frames did not help.

## Upgrading and reverting

- NPU: there is no `sysupgrade` for this slot layout. Reinstall the p1 image
  with `install-npu.sh` (needs the stock NPU running, see
  [install.md](install.md)), or replace `/boot/Image` and the DTB on p1 for a
  kernel-only change.
- Back to Sophos: [recovery.md](recovery.md).

## Known limits

- The SFP cage is described but untested (no module available).
- Resetting the NPU reboots the x86.
- The x86 root filesystem is one 3.7 GB ext4 on the swap area; there is
  no swap.
- No root password on either system by default.
