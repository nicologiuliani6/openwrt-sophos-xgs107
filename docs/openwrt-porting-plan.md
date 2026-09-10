# OpenWrt on the XGS 107w — porting plan

> ## ⚠️ FINAL GOAL — NOT YET ACTIONABLE
>
> Nothing in this document should be started until the ARM side is
> confirmed booting and forwarding packets on our own unit. Writing
> OpenWrt packaging around a bring-up that hasn't happened yet is wasted
> work. This is a written plan only, kept so the target stays in view.
>
> **Gate to open before any of this begins:**
> ARM side boots → CPSS runs → `ip link set eth0 up` on the ARM side
> forwards traffic → repeat on all 8 ports + SFP.

---

## 1. What "OpenWrt support" actually means for this box

The split-brain architecture (see [prior-art.md](prior-art.md)) means an
OpenWrt image here has **two halves**, and only one of them is a normal
OpenWrt target:

| Half | What runs | OpenWrt's role |
|---|---|---|
| x86 | OpenWrt itself, `x86/64` target | Normal. Already works today. |
| ARM switch | Its own Linux + CPSS agent, on its own eMMC | **Not** built by OpenWrt in the obvious sense. A payload OpenWrt must ship, provision, and talk to. |

So this is **not** a new OpenWrt target board. It is `x86/64` plus a
device-specific package that carries and manages a coprocessor payload.
Framing it that way avoids a lot of wrong turns.

The ARM firmware is genuinely separate from OpenWrt's own kernel and
userland. That is a shape OpenWrt has handled before — as *firmware
blobs plus a control daemon*, not as a second target in the same image.

---

## 2. Starting point in the OpenWrt tree

**Target: `x86/64`, generic subtarget.** No new target, no new arch.

Nothing in OpenWrt currently matches "x86 host + ARM coprocessor switch
with its own OS". Searching turned up no existing device profile with
this shape. Closest available reference points, none exact:

- **`x86/64` generic** — the base. All x86 device support (BIOS, storage,
  wifi, USB) is already there.
- **Marvell Prestera / switchdev work outside OpenWrt** — the ecosystem
  lives in DENT (`dentproject/dentOS`), Marvell's `switchdev-prestera`,
  and `switchdev-buildroot`, all Buildroot- or ONL-based, not OpenWrt.
  These are where the switch-side knowledge is, and they are the source to
  borrow from.
- **`mvebu` Prestera devices** (e.g. MikroTik CRS3xx, 98DX3236 family) —
  these run OpenWrt *on the Prestera SoC's own ARM core as the main CPU*.
  Opposite topology to ours (there the ARM is the host, here it is a
  coprocessor). Still useful for: prestera kernel driver integration,
  DSA/switchdev configuration, and how port mapping is expressed.
- **Predecessor-generation Sophos hardware** — XG-series desktop units
  reportedly run OpenWrt fine, including LTE and wifi, because they use
  Intel NICs and have no NPU at all. Confirms the x86 half is easy; tells
  us nothing about the switch.

**Conclusion: no prior OpenWrt device with this architecture exists.** We
would be defining the pattern, not following one.

---

## 3. Work breakdown

### Phase A — reproduce bring-up manually (prerequisite, not OpenWrt work)
1. Serial to `NPU COM`, capture the stock boot
   ([npu-com-serial-checklist.md](npu-com-serial-checklist.md)).
2. **Dump stock SPI flash and eMMC to files, off-box.** Non-negotiable.
3. Get the ARM side booting a Linux with CPSS running.
4. Verify forwarding on all 8 ports + SFP (SFP is behind the same switch,
   port 0 or 9).
5. Write down every single command. The absence of exactly this is why
   prior art can't be followed step-by-step.

### Phase B — replace the proprietary payload (the pivotal decision)
The extracted Sophos ARM rootfs + CPSS agent **cannot be redistributed**.
An OpenWrt image containing them can never be published. So:

6. Build kernel + rootfs + CPSS agent from Marvell's
   `switchdev-buildroot` for this SoC.
7. Boot that on the ARM side instead of the Sophos payload.
8. Verify forwarding again.

**If this works**, a redistributable image is possible and the rest of the
plan is straightforward. **If it doesn't**, OpenWrt support degrades to "a
package that provisions a payload the user must extract themselves from
their own Sophos firmware" — legal, but much worse UX, and it will never
be an official OpenWrt image. Test this early; it shapes everything after.

### Phase C — OpenWrt integration
9. **Package the ARM payload.** A device-specific package (`sophos-xgs-npu`
   or similar) carrying kernel + rootfs + CPSS agent for the ARM side.
   Built from source via a new OpenWrt package Makefile wrapping the
   Marvell sources, if Phase B succeeds.
10. **Provisioning path.** Decide how the payload reaches the ARM eMMC:
    - one-time flashing utility run by the user (simplest, most likely);
    - or load-at-boot over PCIe, if the ARM side can be made to accept a
      payload that way rather than booting from eMMC.
    Serial transfer as used in prior art is a bring-up technique, not a
    shipping mechanism.
11. **Boot-time orchestration.** A procd init script on the x86 side that
    starts/monitors the ARM side, waits for CPSS readiness, and fails
    loudly rather than silently leaving 8 dead ports.
12. **Host-side driver.** Whether the mainline `prestera` driver (with
    `0x7080` added) becomes useful once the ARM side is alive is an open
    question — see the README. If it binds, ports may appear as switchdev
    netdevs on the x86 side; if not, control stays on the ARM side and the
    x86 sees a single trunk link. **These are very different OpenWrt
    integrations** and the answer must come from Phase A/B, not guesswork.
13. **Port mapping / `board.d`.** Map physical labels (1/LAN, 2/WAN, 3/DMZ,
    4–8, F1/SFP) to interfaces, with a sane default LAN/WAN split.
14. **VLAN handling.** Prior art hit VLANs not persisting across reboot.
    Whatever the fix is, it has to survive OpenWrt's config-driven model,
    where VLANs get reapplied from UCI on every boot.
15. **Image + device profile.** An `x86/64` profile pulling in the above,
    plus wifi for the "w" model.

### Phase D — upstreaming
16. `0x7080` to `prestera_pci.c` upstream, if it proves genuinely useful.
17. OpenWrt device page + profile; forum thread; toh entry.
18. Publish the write-up the community is still waiting for.

---

## 4. Main risks

| Risk | Impact |
|---|---|
| Open CPSS agent won't drive `0x7080` | No redistributable image; support stays a DIY package. **Biggest single risk.** |
| ARM payload must live on eMMC, no PCIe load path | Provisioning becomes a flashing step, not a boot step. Awkward but workable. |
| Bricking the ARM side during Phase A | Project over, unless SPI + eMMC were dumped first. Hence step 2. |
| L3 offload never works | Falls back to L2 switching + x86 doing the routing. Still a working 8-port box — an acceptable outcome. |
| Board revisions differ | Pinouts and payloads may not transfer between units or models. |

---

## 5. Not doing

- No new OpenWrt target or subtarget. `x86/64` is correct.
- No attempt to run OpenWrt *on* the ARM side as the main OS. It is a
  coprocessor; it needs CPSS, not an OpenWrt userland.
- No reimplementation of CPSS. That is a multi-year project, and Marvell
  already publishes an open agent — try it first.
- No packaging work before Phase A and B are done on our own hardware.
