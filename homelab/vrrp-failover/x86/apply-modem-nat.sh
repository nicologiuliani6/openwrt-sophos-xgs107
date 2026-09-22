#!/bin/sh
# Run once on the x86 (as root, over SSH) to make the USB TIM modem a
# persistent interface and NAT LAN traffic through it. Idempotent.
#
# Before this: eth0 (the modem) only got an address from a manual, non-
# persistent `udhcpc`, and the "wan" firewall zone pointed at the networks
# "wan"/"wan6", which do not exist on this box, so masquerade never applied
# to anything.
set -eu

uci -q batch <<'EOT'
set network.modem=interface
set network.modem.device='eth0'
set network.modem.proto='dhcp'
commit network
EOT

case " $(uci -q get firewall.@zone[1].network) " in
*' modem '*) ;;
*)
	uci -q batch <<'EOT'
del_list firewall.@zone[1].network='wan'
del_list firewall.@zone[1].network='wan6'
add_list firewall.@zone[1].network='modem'
commit firewall
EOT
	;;
esac

/etc/init.d/network restart
/etc/init.d/firewall restart
