# OpenDragy — GPS configuration (u-blox M10 / MG-A01)

OpenDragy firmware **auto-configures** the module on every boot:

| Setting | Value |
| :--- | :--- |
| Output | **UBX only** (NMEA off) |
| Message | **NAV-PVT** @ every epoch |
| Rate | **10 Hz** (`CFG-RATE-MEAS` = 100 ms) |
| Dyn model | **Automotive** |
| GNSS | GPS + Galileo + GLONASS + BeiDou |
| SBAS | On (**EGNOS** in Europe) |
| Baud | **115200** (assumed; set once if module is still at 38400) |

You normally **do not** need u-center. Use this guide only to fix baudrate or verify PVT on USB.

---

## Baudrate (one-time, if needed)

Factory MG-A01 is often **115200** already. Chip default can be **38400**.

1. Flash `SerialToSerial.ino` (GPIO 4/5) if you need ESP passthrough, **or** connect the GPS USB port directly to the PC.
2. In **u-center 2**, set `CFG-UART1-BAUDRATE` = `115200` → RAM + BBR + Flash → **Send**.
3. Reconnect at 115200.

---

## Optional verification

In u-center (USB or passthrough @ 115200):

* Messages: **UBX-NAV-PVT** present ~10×/s
* NMEA GGA/RMC: absent (or rate 0)
* `hAcc` in metres looks sane outdoors (often &lt; 5 m with clear sky + EGNOS)
* `fixType` = 3D, `gnssFixOK` set

---

## Why not 25 Hz on MG-A01?

MG-A01 is an M10 Ultra rated for **10 Hz** with up to 32 satellites. Pushing higher rates on M10 typically cuts the satellite budget. Dragy Pro markets up to 25 Hz on its hardware; for this module, **10 Hz PVT + multi-GNSS + SBAS** is the accuracy-first choice.

---

## Legacy NMEA note

Older OpenDragy builds used GGA+RMC over BLE. Current firmware uses binary **ODGP** packets derived from NAV-PVT. The Flutter app still accepts legacy NMEA if an old firmware is flashed.
