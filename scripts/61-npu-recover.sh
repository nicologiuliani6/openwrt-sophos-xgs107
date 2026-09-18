#!/bin/sh
# Return the NPU to stock after a kexec test, from the PC.
# Reboots the NPU over x86 ttyS2: SysRq-b (bench initramfs) and a typed
# "reboot -f" (OpenWrt, whose SysRq is disabled). When the NPU drops off
# PCIe, SFOS on the x86 crashes and reboots. This waits for its console
# login, logs in (admin) and opens the advanced shell (menu 5 -> 3). If
# SFOS survives, it waits until the stock NPU answers on mvmgmt0 instead.
# See scripts/60-npu-kexec.md.
set -u
cd "$(dirname "$0")/.."
LOG=logs/x86-console-recover-$(date +%Y%m%d-%H%M%S).log
send() { sg dialout -c "python3 scripts/40-console-send.py --name sfos-recover --idle ${2:-4}" <<EOT
$1
EOT
}
send 'python3 -c "import termios,os,time; fd=os.open(\"/dev/ttyS2\",os.O_RDWR|os.O_NOCTTY); termios.tcsendbreak(fd,0); time.sleep(0.3); os.write(fd,b\"b\"); os.close(fd); print(\"SYSRQ-B sent\")"; printf "\\rreboot -f\\r" > /dev/ttyS2' >/dev/null
sg dialout -c "stty -F /dev/ttyUSB0 38400 raw -echo clocal; exec timeout 900 cat /dev/ttyUSB0" > "$LOG" &
CAT=$!
n=0
until grep -aq "Password:" "$LOG"; do
	kill -0 $CAT 2>/dev/null || { echo "no login prompt within 15 min"; exit 1; }
	sleep 5; n=$((n+5))
	if [ $n -ge 240 ] && ! grep -aq "BIOS\|GRUB\|Booting" "$LOG"; then
		# SFOS did not crash: wait for the stock NPU on mvmgmt0
		kill $CAT 2>/dev/null
		until send 'timeout 10 xgs-ssh.sh uname -r' 14 | grep -q '^4\.14'; do sleep 10; done
		echo "NPU back on stock, SFOS still up"
		exit 0
	fi
done
kill $CAT 2>/dev/null
sleep 3
send admin >/dev/null; send 5 >/dev/null; send 3 | tail -1
