#!/bin/sh
# Moves the LAN default route when this NPU's VRRP state (VRID 1, 192.168.88.254
# on br-lan) changes: Master -> the x86/USB-modem NAT gateway, Backup -> the
# MikroTik. Started by /etc/init.d/vrrp-route-failover (procd, respawn), after
# frr (START=96).
#
# DNS caveat: LAN clients still point at 192.168.88.1 (MikroTik) for DNS. If
# the MikroTik is down, the route flips but name resolution does not, until a
# resolver is added on the x86/NPU side. Not handled here on purpose.

GW_MASTER=192.168.88.6   # x86 (NAT to the USB TIM modem)
GW_BACKUP=192.168.88.1   # MikroTik
DEV=br-lan

STATE_PREV=""
while true; do
	STATE=$(vtysh -c 'show vrrp json' 2>/dev/null | jq -r '.[0].v4.status // empty')
	if [ -n "$STATE" ] && [ "$STATE" != "$STATE_PREV" ]; then
		case "$STATE" in
		Master)
			ip route replace default via "$GW_MASTER" dev "$DEV"
			logger -t vrrp-failover "MASTER: rotta via x86/modem USB ($GW_MASTER)"
			;;
		Backup)
			ip route replace default via "$GW_BACKUP" dev "$DEV"
			logger -t vrrp-failover "BACKUP: rotta via MikroTik ($GW_BACKUP)"
			;;
		esac
		STATE_PREV="$STATE"
	fi
	sleep 3
done
