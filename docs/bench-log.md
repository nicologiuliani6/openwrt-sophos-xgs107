# Bench log

Chronological record of everything done on the physical unit: what was
tried, what came out, what it means. Raw captures are in `logs/`.

Unit: Sophos XGS 107w, mainboard `XGS 87(W) 107(W) 1.40`.

---

## 2026-09-18 — first session

### 1. Case opened, `NPU COM` located

- Photo: `logs/npu-com-header.jpg`.
- Header is **4 pins, all physically fitted** (not 3). Silkscreen: `4` on
  the left end (next to the unpopulated 2-hole footprint `J10`), `1` on the
  right end (next to `J20` and the M.2 slot).
- Left to right, pins are therefore **4, 3, 2, 1**. The prior-art pinout
  ("pin 1 empty, 2 GND, 3 RXD, 4 TXD") uses the silkscreen numbering: the
  pin it calls "empty" is the rightmost and is physically present, just
  unused (could be VCC — never connect it).
- Pitch looks standard 2.54 mm; regular dupont jumpers fit.
- Nearby: Micron DRAM `D9WFH` ×3 (U51, U53, U54) — probably the ARM side's
  RAM, unverified. SOIC-8 `U41` marking not legible yet (SPI flash
  candidate).

Other board observations:

- Wi-Fi: M.2/mini-PCIe card under a black heatsink, U.FL `CH0`/`CH1` wired,
  `CH2` unused.
- 4× `HN4824CG` Ethernet magnetics for the 8 copper ports; two small black
  heatsinks next to them (PHY or switch silicon, not removed).
- An unidentified **2×4 pin header** was seen in a blurry photo — candidate
  SPI/JTAG programming header. Needs a sharp photo with its silkscreen.

**Lesson learned:** count pins by the silkscreen numbers, never by other
people's photos. A blurry, angled prior-art photo led to a left-to-right
reading that was the reverse of the silkscreen. The same photo, read
correctly, shows the 3-wire block on the three *left* pins (4-3-2) with the
right one (1) free — consistent with the text.

### 2. Arduino Uno as a receive-only serial adapter

USB-TTL adapters (FT232RL, USB-RJ45 console cable) ordered, not yet
arrived. Stopgap: an Arduino Uno R3 clone (Elegoo) in passthrough mode.

- `RESET` jumpered to `GND` on the Arduino holds the ATmega328P in reset;
  the on-board ATmega16U2 USB-serial bridge is then exposed on D0/D1.
- Enumerates as `/dev/ttyACM0`.
- **Wiring is NOT crossed in this mode**: the Arduino's TX/RX labels are
  from the 328P's point of view. Board TX goes to Arduino **pin 1
  ("TX→1")**.
- Arduino pin 0 must stay unconnected: it is the 16U2's 5 V output and
  would fight the board's 3.3 V TX line (the Uno's on-board 1 kΩ series
  resistors limit the current, but not verified on this clone).

Correct wiring used:

```
XGS pin 4 (TXD)  -> Arduino pin 1 (TX→1)
XGS pin 3 (RXD)  -> nothing
XGS pin 2 (GND)  -> Arduino GND
XGS pin 1        -> nothing
Arduino RESET    -> Arduino GND
```

Host setup: user added to `dialout` (takes effect after re-login; until
then run tools via `sg dialout -c "..."`). A per-device ACL set with
`setfacl` is lost whenever the Arduino is re-plugged.

**Loopback self-test** (pins 0 and 1 jumpered, XGS wire removed): a test
string sent from the PC came back intact at both 115200 and 9600. The
Arduino adapter chain is confirmed working.

### 3. `NPU COM` captures — nothing received

| Capture | Wiring | Result |
|---|---|---|
| `npu-com-boot-20260918-1925.log` | **wrong** (board TX on Arduino pin 0, board RX on GND, GND not common) | two isolated `0x00` at power events, 15 random bytes while wires were being moved — noise, not data |
| `npu-com-boot-20260918-2050-provaA.log` | correct, 115200 | 0 bytes |
| `npu-com-20260918-2053…/2100…/2104…-115200.log` | correct, live via `scripts/30-npu-console.sh` | 0–7 bytes, almost all `0x00` — noise |
| `npu-com-20260918-211910-sfosboot.log` | correct, 115200, **during a full SFOS boot** | 0 bytes |

Important correction: the early `0x00` bytes were first read as proof the
TX line was live. They were captured with the wrong wiring and no common
ground, so they are **noise from power transitions**, not evidence of
anything. The board's TX line has never been seen to carry data.

Not yet tried: board pin 3 as TX ("test B"), other baud rates with data
present, a voltage measurement of the header.

### 4. x86 console found on the micro-USB port

- The XGS micro-USB port is an **official Sophos serial console** (Sophos
  KB "Set up a serial connection with a console cable").
- On-board bridge: **Prolific PL2303, USB ID `067b:23a3`**, driver `pl2303`
  (in-kernel), shows up as `/dev/ttyUSB0`. Single port — x86 only, not the
  ARM side.
- Needs the XGS powered; with the XGS off it does not enumerate.
- **38400 8N1** (fixed in BIOS).
- Sophos: if both micro-USB and RJ45 console are connected, output goes to
  the micro-USB only.
- A charge-only micro-USB cable produces no USB event at all — use a data
  cable.

```sh
sg dialout -c "picocom -b 38400 -g logs/x86-console-$(date +%Y%m%d-%H%M).log /dev/ttyUSB0"
```

### 5. What the x86 side shows

Logs: `x86-console-20260918-2112.log`, `x86-console-20260918-2114.log`.

- The unit powers on and boots fine.
- BIOS is **AMI Aptio**, with serial console redirection. Over serial the
  full-screen UI renders poorly and function/arrow keys are unreliable. It
  was entered once by accident and left via *Exit Without Saving* — no
  BIOS setting was changed.
- **SFOS is installed and boots.** Relevant boot lines:
  ```
  Loading network interface drivers...duration 19
  Checking for NPU uboot mismatch...
  Loading Kdump kernel
  ```
- **"Checking for NPU uboot mismatch"** means SFOS on the x86 checks — and
  presumably reflashes — the ARM side's u-boot. This is the most likely
  meaning of the prior art's *"Sophos's own USB-SPI tool that's on the
  board"*: an x86-side SFOS tool, not a separate part.
- Firmware: **SFOS 19.5.4 MR-4 (Build 718)**, model `XGS107w`.

### 6. Console password reset

The previous owner's admin password was unknown. Official Sophos
procedure, which leaves the configuration intact:

1. At `Password:` type `RESET`.
2. Hidden reset menu → **4. Reset password for admin user** → `y`.
3. Log in with the factory password `admin`.

Options 1–3 of that menu are full factory resets and were **not** used.

Main console menu afterwards: 1 Network, 2 System, 3 Route, 4 Device
Console, 5 Device Management, 6 VPN, 7 Shutdown/Reboot.

### 7. SFOS recon (read-only, from the x86 advanced shell)

Console driven by `scripts/40-console-send.py` over the micro-USB console.
Full output: `logs/sfos-recon-20260918.log`. Results are consolidated in
[hardware-architecture.md](hardware-architecture.md). Headline findings:

- `[11ab:7080]` is a **Marvell CN9130** SoC in PCIe endpoint mode, not a
  Prestera. The switch is a **Marvell 88E6193X** on the CN9130's MDIO bus.
- The NPU runs Linux 4.14.207 (Marvell SDK 10.22.03) from eMMC slot p3,
  booted by a stock u-boot on SPI (`mtd0`).
- **NPU console = x86 `/dev/ttyS2` @ 115200** (see
  `/bin/xgs-npu-serial-logger.sh`).
- `xgs-ssh.sh "<cmd>"` gives a root shell on the NPU over `mvmgmt0`.
- "Checking for NPU uboot mismatch" is `/bin/xgs-check-uboot-version.sh`.
  It compares `strings` of the platform u-boot image with
  `xgs-ssh.sh strings /dev/mtd0`. Reflashing is done by
  `xgs-npu-uboot-update.sh`. This is the "Sophos USB-SPI tool" of the prior
  art.
- Host drivers are Sophos-Proprietary, built only for 4.14.277.
- `/opt/sophos/npu-fw` (the default `SOPHOS_FW_DIR`) does not exist on this
  install. Where the NPU images live still has to be found.

Network note: the XGS **Port1 is SFOS's LAN and runs a DHCP server**
(`dhcpd`). Do not plug Port1 into another network. **Port2 and Port4 are
WAN ports with DHCP clients** (`udhcpc`); use Port2 to join the home LAN.

---

## Open questions after session 1

- [ ] Why is `NPU COM` silent? Low priority now: the NPU console is
      reachable as x86 `/dev/ttyS2`, and the stock NPU kernel does log to
      `ttyS0`. Candidates: 1.8 V logic not seen by the Arduino, a mux or
      CPLD, or TX on pin 3.
- [x] What does SFOS see? Answered in §7 and hardware-architecture.md.
- [ ] Where does SFOS keep the NPU u-boot and rootfs images?
- [ ] Sharp photo of the 2×4 header and of `U41`.
