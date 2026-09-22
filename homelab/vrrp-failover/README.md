# VRRP failover to the USB TIM modem

**Site-specific to the owner's homelab.** Not part of the default image or of
`openwrt/apply.sh`: it hardcodes the owner's own addresses
(`192.168.88.0/24`, MikroTik `.1`, the x86 module NAT-ed to a USB TIM modem)
and only makes sense on that network. Anyone else building this project's
default image does not get any of this; see [../../README.md](../../README.md)
and [../../docs/](../../docs/) for the general project.

## What it does

The Sophos NPU runs FRR's `vrrpd` for VRID 1 on `br-lan`, virtual IP
`192.168.88.254`. Normally the MikroTik (`192.168.88.1`) is VRRP Master and
the NPU is Backup. When the MikroTik goes down, the NPU becomes Master and a
watcher script moves the LAN's default route to the x86 module
(`192.168.88.6`), which NATs it out over its USB TIM modem (`eth0`, DHCP).
When the MikroTik comes back, the route moves back.

Tested end-to-end by physically unplugging the MikroTik: failover succeeded,
about 5 packets lost during the ~3-4 s convergence, then stable on the USB
modem. **Open, not blocking**: LAN clients still get DNS from the MikroTik
(`192.168.88.1`); if it's down, the route flips but name resolution doesn't,
until a resolver is added on the x86/NPU side.

## Three things had to be fixed beyond "add the kernel module"

The initial assumption was that `CONFIG_MACVLAN=m` was the only missing
piece. It wasn't:

1. **The kernel module** — genuinely missing, now in the default NPU kernel
   config (`build/config/npu.config`, `CONFIG_PACKAGE_kmod-macvlan=y`), so
   it needs no homelab-specific step.
2. **`zebra`/`vrrpd` have no Linux capabilities.** They run as the
   unprivileged `network` user; this OpenWrt `frr` package's own
   `/etc/init.d/frr` does not grant any. Without `CAP_NET_ADMIN`/
   `CAP_NET_RAW` they cannot create or bring up network interfaces at all.
3. **`vrrpd` does not create the macvlan interface itself** — checked by
   `strings` on the binaries: `zebra`'s only macvlan code is for VXLAN/EVPN,
   unrelated to VRRP; `vrrpd` only binds a socket to an *existing* macvlan
   device found by its virtual MAC address. The interface has to be created
   by hand (or, here, by `vrrp-iface` at boot).

A fourth thing surfaced only during the first real failover test: the `lan`
firewall zone only knows about the `lan` network (`br-lan`), not the
`vrrp1-v4-1` macvlan child of it, so forwarded traffic was rejected during a
failover (found with `nft monitor trace`). `vrrp-iface` also adds the device
to that zone.

## Files

- `npu/etc/init.d/vrrp-iface` (START=94, before frr's START=95): idempotent.
  Applies the capabilities from `npu/etc/capabilities/{zebra,vrrpd}.json`
  with `setcap` (frr's daemons are not procd-managed, so procd's own
  `capabilities=` mechanism does not reach them; the JSON is only the
  declared source of truth, applied by this script), creates/ups the
  `vrrp1-v4-1` macvlan interface on `br-lan`, and adds it to the `lan`
  firewall zone.
- `npu/etc/hotplug.d/iface/95-vrrp-iface`: re-runs `vrrp-iface start` when
  the `lan` logical interface comes back up (e.g. after
  `/etc/init.d/network restart`), which otherwise silently drops the
  macvlan child of `br-lan` and breaks VRRP until the next reboot.
- `npu/etc/init.d/vrrp-route-failover` (START=96, procd, respawn) running
  `npu/usr/sbin/vrrp-route-failover.sh`: polls
  `vtysh -c 'show vrrp json' | jq -r '.[0].v4.status'` every 3 s and moves
  the default route on a state change. Logs with `logger -t vrrp-failover`
  (`logread | grep vrrp-failover`).
- `x86/apply-modem-nat.sh`: makes the USB modem's `eth0` a persistent `dhcp`
  interface (`modem`) and points the `wan` firewall zone's masquerade at it
  instead of the nonexistent `wan`/`wan6` networks it shipped with.

`vrrp-iface` and `vrrp-route-failover.sh` need `jq` and `setcap` (package
`libcap-bin`) on the NPU: `apk add jq libcap-bin`.

## Installing on the live devices

```sh
# NPU (192.168.88.5)
ssh root@192.168.88.5 apk add jq libcap-bin
scp -r npu/etc/capabilities/*.json root@192.168.88.5:/etc/capabilities/
scp npu/etc/init.d/vrrp-iface npu/etc/init.d/vrrp-route-failover root@192.168.88.5:/etc/init.d/
scp npu/etc/hotplug.d/iface/95-vrrp-iface root@192.168.88.5:/etc/hotplug.d/iface/
scp npu/usr/sbin/vrrp-route-failover.sh root@192.168.88.5:/usr/sbin/
ssh root@192.168.88.5 '
	chmod +x /etc/init.d/vrrp-iface /etc/init.d/vrrp-route-failover \
		/etc/hotplug.d/iface/95-vrrp-iface /usr/sbin/vrrp-route-failover.sh
	/etc/init.d/vrrp-iface enable && /etc/init.d/vrrp-iface start
	/etc/init.d/vrrp-route-failover enable && /etc/init.d/vrrp-route-failover start
'

# x86 (192.168.88.6)
scp x86/apply-modem-nat.sh root@192.168.88.6:/tmp/
ssh root@192.168.88.6 'sh /tmp/apply-modem-nat.sh'
```

The NPU also needs `/etc/frr/frr.conf` to define VRID 1 on `br-lan` with
`vrrp 1 ip 192.168.88.254` (existing FRR/VRRP config, not part of this
overlay) and the `frr`/`frr-vrrpd` packages installed.

**Not yet automated**: none of this survives a full `install-npu.sh`
reflash of the NPU's eMMC slot, since it lives outside `openwrt/npu/base-
files/` on purpose (see the top of this file). After a reflash, redo the
"Installing" steps above.
