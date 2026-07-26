# OpenDragy — GPS configuration (u-blox M10 / MG-A01)

OpenDragy firmware **auto-configures** the module on every boot (`configureGpsModule()` in [`OpenDragy.ino`](OpenDragy.ino)). CFG-VALSET uses layers **RAM + BBR + Flash** (`0x07`).

| Setting | Value (as sent by firmware) |
| :--- | :--- |
| UART1 out | **UBX on**; **NMEA on temporarily**, then **NMEA out off** after first real NAV-PVT |
| UART1 in | **UBX + NMEA** (kept on — needed for aiding / tools) |
| Message | **NAV-PVT** on UART1 every epoch (`CFG-MSGOUT-UBX_NAV_PVT_UART1` + legacy `CFG-MSG`) → BLE **ODGP** |
| Rate | `CFG-RATE-MEAS` = **100 ms** (10 Hz), `CFG-RATE-NAV` = **1** |
| Dyn model | **Automotive** (`CFG-NAVSPG-DYNMODEL` = 4) |
| NMEA (temp) | **GGA + RMC** rate 1; VTG / GSA / GSV / GLL off |
| NMEA (after PVT) | GGA + RMC rate 0; `CFG-UART1OUTPROT-NMEA` = false |
| GNSS | GPS + Galileo + GLONASS + BeiDou + SBAS signal enables (BeiDou may **NAK** on some M10 builds) |
| SBAS | Enabled + `USE_TESTMODE` + `USE_DIFFCORR` (**EGNOS** in Europe) |
| Baud | ESP opens **115200**; if no UART bytes for ~1.5 s → try **38400**, set baud to 115200, re-CFG |

You normally **do not** need u-center. Use this guide to fix baudrate, verify PVT, or recover a stuck module.

**Wiring (ESP32-S3):** GPS **TX → GPIO 4**, GPS **RX → GPIO 5**, GND, 3.3 V.

---

## Baudrate (one-time, if needed)

Factory MG-A01 is often **115200** already. Chip default can be **38400**.

1. Flash [`serial_to_serial/SerialToSerial.ino`](serial_to_serial/SerialToSerial.ino) as a **separate** sketch (do not leave it next to `OpenDragy.ino`), **or** use the GPS USB port directly.
2. In **u-center 2**, set `CFG-UART1-BAUDRATE` = `115200` → RAM + BBR + Flash → **Send**.
3. Reconnect at 115200.

Optional: run [`tools/configure_gps_pvt.py`](tools/configure_gps_pvt.py) against the SerialToSerial bridge (COM @ 115200). It pushes the **same CFG keys** as boot (including temp GGA/RMC). It does **not** run the firmware’s “disable NMEA after PVT” step — so you may still see GGA/RMC next to NAV-PVT until you flash product firmware again.

---

## Optional verification

**u-center** (USB or passthrough @ 115200):

* **UBX-NAV-PVT** ~10×/s
* After **product firmware** has locked PVT: NMEA GGA/RMC absent (or rate 0)
* `hAcc` sane outdoors (often &lt; 5 m with EGNOS; sub‑metre is common)
* `fixType` = 3D, `gnssFixOK` set

**OpenDragy USB serial** (product firmware):

```text
[GPS] src=PVT ... pvt=~10 ... nmea=0
```

`src=NMEA` means PVT has not stuck yet (firmware keeps re-requesting NAV-PVT).

---

## Why not 25 Hz on MG-A01?

MG-A01 is an M10 Ultra rated for **10 Hz** with up to 32 satellites. Higher rates on M10 typically cut the satellite budget. For this module, **10 Hz PVT + multi-GNSS + SBAS** is the accuracy-first choice.

---

## App aiding (no u-center)

On BLE connect the Flutter app injects (RX characteristic → GPS UART):

1. **UBX-MGA-INI-TIME_UTC** — phone UTC, ~1 s accuracy, trusted flag  
2. **UBX-MGA-INI-POS_LLH** — phone GNSS/network position when available; else last saved OpenDragy fix  

Grant location permission for best cold-start behaviour.

---

## Legacy NMEA note

Older OpenDragy builds used GGA+RMC over BLE. Current firmware uses binary **ODGP** from NAV-PVT. The Flutter app still accepts legacy NMEA if an old firmware is flashed.
