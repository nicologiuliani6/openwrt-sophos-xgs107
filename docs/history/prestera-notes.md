> **Obsolete.** These notes are about the mainline `prestera` driver, which does not apply
> to this hardware (the NPU is a CN9130 + 88E6193X, not a Prestera switch). Kept for the record.

# Mainline `prestera` driver — reference notes

Source: `drivers/net/ethernet/marvell/prestera/prestera_pci.c` (Linux
mainline, Dual BSD/GPL license)

## Key constants

- Loader ready magic: `0xf00dfeed` (`PRESTERA_LDR_READY_MAGIC`)
- FW ready magic: `0xcafebabe` (`PRESTERA_FW_READY_MAGIC`)
- FW header magic: `0x351D9D06` (`PRESTERA_FW_HDR_MAGIC`)
- Supported FW version at time of writing: 4.1 (falls back to 4.0)
- Firmware path format: `mrvl/prestera/mvsw_prestera_fw-v%u.%u.img`
  (ARM64 variant: `mvsw_prestera_fw_arm64-v%u.%u.img`, only for the
  98DX35xx family — probably not relevant to us but worth checking)

## BAR layout

- `PRESTERA_PCI_BAR_FW = 2`
- `PRESTERA_PCI_BAR_PP = 4` (packet processor registers)
- Some newer devices ("AC5X") use BAR2 split in half instead of a
  separate BAR4 — see `prestera_pci_pp_use_bar2()` in the source, keyed
  off specific device IDs. Worth checking which layout `0x7080` uses
  once we can read `lspci -vvv` BAR sizes.

## Loader protocol (high level)

1. Host waits for `ldr_ready` register == `0xf00dfeed`
2. Host reads ring buffer offset/size from loader registers
3. Host requests firmware file via standard Linux firmware API
   (`request_firmware_direct`), checks the `0x351D9D06` magic header
4. Host streams the firmware image into the ring buffer in 1024-byte
   blocks (`PRESTERA_FW_BLK_SZ`), tracking write index
5. Host polls loader status register for completion / CRC-valid /
   out-of-memory flags
6. Once loaded, host waits for `fw_ready` register == `0xcafebabe`
7. Host reads command/event queue offsets and sizes from fixed register
   offsets, sets up cmd/evt queues
8. Normal operation: command/reply via `PRESTERA_CMDQ_*` registers,
   async events via `PRESTERA_EVTQ_*` registers + MSI IRQ

## Supported PCI device IDs (as of last check)

```c
#define PRESTERA_DEV_ID_AC3X_98DX_55   0xC804
#define PRESTERA_DEV_ID_AC3X_98DX_65   0xC80C
#define PRESTERA_DEV_ID_ALDRIN2        0xCC1E
#define PRESTERA_DEV_ID_98DX7312M      0x981F
#define PRESTERA_DEV_ID_98DX3500       0x9820
#define PRESTERA_DEV_ID_98DX3501       0x9826
#define PRESTERA_DEV_ID_98DX3510       0x9821
#define PRESTERA_DEV_ID_98DX3520       0x9822
```

Our chip: `0x7080` — NOT in this list. First experiment: add it and see
if the loader magic numbers show up at all when probed at the expected
BAR2/BAR4 offsets.

## Where to get the driver source and firmware

- Driver: https://github.com/torvalds/linux/tree/master/drivers/net/ethernet/marvell/prestera
- Firmware (official Marvell switchdev repo):
  https://github.com/Marvell-switching/switchdev-binaries
- Firmware (linux-firmware, Debian/Fedora packaged):
  `firmware-marvell-prestera` (Debian), `mrvlprestera-firmware` (Fedora)
- Upstream driver announcement / design rationale (LWN):
  https://lwn.net/Articles/830682/
