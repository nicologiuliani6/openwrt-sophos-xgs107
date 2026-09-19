# Installation

Goal: both modules of a stock XGS 107w (SFOS) end up running OpenWrt, with
the stock Sophos slot still bootable on the NPU as a fallback.

**Time:** about 30 minutes with a prebuilt `dist/`, plus the backup
(25 minutes for the full eMMC) and, if the images have to be built, an hour or
two.

**You need**

- the appliance, powered, with a network cable between **panel port 2**
  (WAN) or any port and the PC (or a router the PC is on): the x86's only
  network under SFOS is through the NPU;
- a PC (Linux) on that network, with `python3`, `curl`, `git` and, for the
  build, the packages of [build.md](build.md). Its firewall must let the
  appliance reach TCP ports 8000 (and 8001 for the backup);
- the x86 console: micro-USB cable to the PL2303 port (38400 8N1) or the RJ45
  console. Any terminal works (`picocom -b 38400 /dev/serial/by-id/usb-Prolific*`).
  For `./install.sh --serial` your user must be in the `dialout` group
  (`sudo usermod -aG dialout $USER`, log in again); another device:
  `XGS_CONSOLE=/dev/ttyUSB1 ./install.sh --serial`;
- the SFOS admin password (you set it during the first setup; if lost, see
  [recovery.md](recovery.md));
- `dist/` with the installers and images: `./install.sh` builds it for you
  the first time ([build.md](build.md); an hour or two, and 30 GB of disk per
  target), or copy a finished `dist/` into the repository.

**What is written**

| Where | What | Undone by |
|---|---|---|
| NPU eMMC `p1` | OpenWrt | restoring the p1 backup, or just ignoring it |
| NPU U-Boot env (SPI `mtd1`) | four variables: OpenWrt first, stock as fallback | `fw_setenv` or the env backup |
| x86 swap area (SFOS `/dev/swap`, 3.8 GB) | OpenWrt root filesystem | – (it was swap) |
| x86 MBR entry #3, `/boot/openwrt/`, `grub.cfg` | boot entry | `/boot/mbr-sda.bak`, `/boot/grub/grub.cfg.sfos` |
| NPU U-Boot (SPI `mtd0`) | **never written** | – |

## 1. Back up (once, before anything)

See [backup.md](backup.md); it works before anything is built. Do not skip
the SPI U-Boot and the eMMC. `./install.sh` looks for
`dumps/npu/mtd0-uboot.bin` and asks before going on without it.

## 2. The one-command path

On the PC, in the repository:

```sh
./install.sh
```

It builds or reuses `dist/`, asks if there is no backup, starts the HTTP
server and shows the two commands to run on the appliance with your PC's
address already filled in (`--pc-ip` if it guesses the wrong one, `--port`
if 8000 is taken). Open the SFOS advanced shell on the x86 console
first (log in as `admin`, menu **5** *Device Management*, then **3**
*Advanced Shell*), then either paste the commands or let the script type them
(`./install.sh --serial`, it drives the console for you and shows the
appliance's output as it comes; the console session is also logged in
`logs/`). Before that, check from the advanced shell that the appliance reaches
the PC: `curl -sI http://PC:8000/`.

## 3. What the two commands do (manual path)

Run **in this order** in the SFOS advanced shell, with the PC serving `dist/`
(`install/serve.sh`, port 8000):

```sh
curl -fsS http://PC:8000/install-x86.sh -o /dev/shm/i.sh && PC=PC sh /dev/shm/i.sh
curl -fsS http://PC:8000/install-npu.sh -o /dev/shm/n.sh && PC=PC sh /dev/shm/n.sh
```

1. `install-x86.sh` downloads the kernel and root filesystem, verifies them
   by md5 in RAM, writes the root filesystem onto SFOS's swap partition,
   **verifies it by reading the raw disk back through a different device
   node**, adds MBR entry #3, copies the kernel to `/boot/openwrt/` and adds
   the default GRUB entry. It refuses to run if any sanity check fails.
2. `install-npu.sh` writes the OpenWrt slot to the NPU's `mmcblk0p1` through
   `xgs-ssh.sh`, verifies its sha256 on the NPU, and sets the U-Boot
   environment. It refuses to run unless the NPU is on stock slot p3.

Neither reboots anything. **Do not reboot SFOS in between**: at every boot
it runs `mkswap` on the area the x86 installer just wrote.

## 4. First boot

**Power-cycle the appliance** (unplug and re-plug both supplies if it has two;
a warm reboot leaves the NPU running). Then:

- the NPU boots OpenWrt from eMMC (about 40 s), the x86 boots OpenWrt
  through GRUB entry `OpenWrt` (about 60 s) and finds the NPU by itself;
- plug a PC into panel port 1 (or 3-8): DHCP gives `192.168.1.x`;
  open <http://192.168.1.1> (NPU / router) and <http://192.168.1.2> (x86 /
  Wi-Fi). User `root`, **no password**: set one (System → Administration).
- panel port 2 is the WAN (DHCP client).

Checks: `ping 192.168.1.1`, `ping 192.168.1.2`; on the NPU `ip link` shows
`p1…p8`, `sfp`, `ntb0`; on the x86 `ip link` shows `ntb0`. See
[usage.md](usage.md) for the Wi-Fi and everything else.

## If something goes wrong

- **The installer aborts**: nothing beyond the failed step was written;
  read the message, fix, run `./install.sh` again (all steps are idempotent).
  [troubleshooting.md](troubleshooting.md) lists the messages.
- **The NPU does not come up on OpenWrt**: U-Boot falls back to stock by
  itself if the kernel cannot be loaded; otherwise [recovery.md](recovery.md).
- **The x86 shows GRUB and boots SFOS**: choose the `OpenWrt` entry (and see
  recovery.md, do not let SFOS finish booting).
