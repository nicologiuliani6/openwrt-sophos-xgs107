# `NPU COM` header — first-connection checklist (ARM/switch side)

The header silkscreened **`NPU COM`** is the UART of the switch's own ARM
CPU. It is **not** the x86 console — the x86 console is the RJ45 rollover
port at 38400 8N1, and it shows nothing of the switch's boot.

> **Safety.** Connecting a 5V adapter to a 3.3V UART, or driving a pin that
> turns out to be a supply rail, can permanently damage the switch ASIC or
> the board. Work through the measurement steps before plugging in any
> adapter, and never skip common ground.

---

## Reference pinout (community-reported — verify, do not assume)

From the r/opnsense thread (see [prior-art.md](prior-art.md)); one unit,
one board revision. Treat as a strong hypothesis to confirm, not as fact
for our board.

```
pin 1: (empty / unpopulated)
pin 2: GND   ->  FTDI GND
pin 3: RXD   ->  FTDI TXD      <- board RX, adapter TX
pin 4: TXD   ->  FTDI RXD      <- board TX, adapter RX
```

Written board-side first, **already crossed**. A 4-position header with
pin 1 unpopulated reads visually as "3 pins" — that matches.

Adapter used successfully: **plain FTDI USB-to-TTL**. Not an SFP
programmer, no special hardware.

The phases below confirm this pinout on our unit. Phase 1–2 are
measurement only and cost ten minutes; a wrong guess costs the appliance.

---

## Equipment

- [ ] USB-serial adapter, **3.3V logic** (selectable adapters: set to
      3.3V). FTDI is the known-good choice here; CP2102/CH340 also fine.
- [ ] Multimeter with continuity (beep) and DC volts.
- [ ] Female-to-female jumper wires — **continuity-test each wire first**.
      In the prior work, a wire broken in the middle cost more time than
      the entire pinout hunt.
- [ ] Terminal: `picocom`, `minicom`, or `screen`.
- [ ] Light and magnification for the silkscreen.

---

## Phase 1 — powered off, both DC inputs unplugged

Wait ~30s for capacitors to drain.

1. **Photograph the header and surrounding silkscreen** into `logs/`.
   Record which physical end is pin 1: square pad (vs. round), a dot, a
   triangle, or a `1` in silkscreen — referenced to a landmark such as the
   Marvell chip or a nearby connector. The empty position should be pin 1;
   if the empty position is at the *other* end, our numbering is mirrored
   relative to the reference and everything shifts.

2. **Confirm GND by continuity.** Continuity mode; one probe on a known
   ground — chassis screw post, RJ45 shell, USB shield. Touch each
   populated pin.
   - Exactly one should beep / read ~0 Ω. Expect it to be **pin 2**.
   - Two beeping, or the beep landing on a different pin than expected →
     **stop**, the board differs from the reference; re-derive from
     scratch rather than adapting.

3. **Sanity-check the other two.** Resistance from each remaining pin to
   GND: TX and RX read high or show a weak pull-up, never a short.

## Phase 2 — powered on, nothing connected to the header

Board powered, **no adapter attached**. DC volts, black probe on the GND
pin from step 2.

4. **Measure the logic level** on pins 3 and 4.
   - **~3.3V idle** → 3.3V UART. Expected. Proceed.
   - **~5V** → level shifter or 5V-tolerant adapter required.
   - **~1.8V** → a 3.3V adapter would overdrive this pin and can damage
     it. Level shifter mandatory. Stop and re-plan.
   - **~0V on both** → UART held low, ARM side unpowered, or wrong header.
     Investigate before connecting anything.

5. **Confirm which is TX.** The board's TX idles high and **dips visibly
   during boot** as it transmits; the board's RX is an input and stays
   static. Watch the meter while power-cycling the appliance — the pin
   that wobbles in the first seconds is the board's TX. Expect **pin 4**.
   A scope or logic analyser settles it instantly if available.

## Phase 3 — connecting

6. **Cross TX and RX** — the single most common mistake:
   ```
   board pin 2 (GND) -> adapter GND
   board pin 4 (TXD) -> adapter RXD
   board pin 3 (RXD) -> adapter TXD
   ```
   Never TX-to-TX. **Do not connect the adapter's VCC to anything** — the
   header has no VCC pin; the board powers itself.

7. **GND first, then the receive path only.** GND, then board TXD →
   adapter RXD. Leave the adapter's TX disconnected for the first boot.
   Listening is read-only: it cannot damage anything and it proves the
   pinout before any pin is driven.

8. **Open the terminal and power-cycle the appliance.**
   ```sh
   picocom -b 115200 /dev/ttyUSB0        # then 57600, 38400, 9600
   ```
   Baud is unconfirmed; **115200 8N1 is the most likely** for a Marvell
   ARM u-boot console. Legible text = correct baud and correct pin.
   Consistent garbage that changes shape with baud = right pin, wrong
   rate. Nothing at any rate = wrong pin; swap pins 3/4 and repeat.

   Expected on success: a u-boot banner, and eventually a shell prompt
   reading **`marvell#`**.

9. **Only once readable output appears**, attach the adapter's TXD to
   board pin 3 and test input — Enter, or a keypress to interrupt the
   bootloader countdown.

---

## What to capture on the first successful boot

```sh
picocom -b 115200 /dev/ttyUSB0 | tee logs/npu-com-boot-$(date +%Y%m%d-%H%M).log
```

- [ ] Bootloader identity and version (stock u-boot? Sophos-modified?).
- [ ] Whether the countdown can be interrupted, and with which key.
- [ ] SoC identification string — the real Marvell part behind `0x7080`.
- [ ] Storage enumeration: eMMC size and partitions, SPI flash chip ID.
      (Reference unit: 2 GB RAM + eMMC on the ARM side.)
- [ ] Whether a kernel boots and a userland comes up as shipped.
- [ ] Any CPSS agent startup messages.
- [ ] `printenv`, and whether **USB and TFTP work in u-boot** — either
      would replace pushing the rootfs over serial, which is slow.
- [ ] Anything resembling the *"USB-SPI tool on the board"* referenced in
      prior art — a u-boot command, a Sophos-specific subcommand, or a
      dedicated header. Open question; the log may answer it.

---

## Do not, until the pinout is confirmed on this board

- Do not connect the adapter's VCC/3.3V/5V line to the header at all.
- Do not connect the adapter's TX before readable output proves the pinout.
- **Read before write.** Do not `sf` / `mmc write` anything from u-boot
  until the current SPI flash and eMMC contents are dumped and saved
  off-box. A bricked ARM side with no known-good image is the one failure
  mode that ends this project — and the stock image is exactly what prior
  art had to extract from firmware to recreate.
