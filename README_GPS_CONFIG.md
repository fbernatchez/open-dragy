# OpenDragy — GPS configuration (u-blox M10 / MG-A01)

OpenDragy firmware **auto-configures** the module on every boot:

| Setting | Value |
| :--- | :--- |
| Output | **UBX** preferred; NMEA briefly left on until first NAV-PVT, then NMEA out off |
| Message | **NAV-PVT** @ every epoch → BLE **ODGP** binary |
| Rate | **10 Hz** (`CFG-RATE-MEAS` = 100 ms) |
| Dyn model | **Automotive** |
| GNSS | GPS + Galileo + GLONASS (+ BeiDou if CFG ACK) |
| SBAS | On (**EGNOS** in Europe) |
| Baud | **115200** (firmware also retries 38400 → bump to 115200 if silent) |

You normally **do not** need u-center. Use this guide to fix baudrate, verify PVT, or recover a stuck module.

---

## Baudrate (one-time, if needed)

Factory MG-A01 is often **115200** already. Chip default can be **38400**.

1. Flash [`serial_to_serial/SerialToSerial.ino`](serial_to_serial/SerialToSerial.ino) (GPIO 4 = GPS TX→ESP RX, GPIO 5 = GPS RX←ESP TX), **or** connect the GPS USB port directly to the PC.
2. In **u-center 2**, set `CFG-UART1-BAUDRATE` = `115200` → RAM + BBR + Flash → **Send**.
3. Reconnect at 115200.

Optional: run [`tools/configure_gps_pvt.py`](tools/configure_gps_pvt.py) against the SerialToSerial bridge (COM port @ 115200) to push the same CFG keys the firmware uses and confirm ACK / NAV-PVT.

---

## Optional verification

In u-center (USB or passthrough @ 115200):

* Messages: **UBX-NAV-PVT** present ~10×/s
* NMEA GGA/RMC: absent (or rate 0) once CFG is applied
* `hAcc` in metres looks sane outdoors (often &lt; 5 m with clear sky + EGNOS; sub‑metre is common)
* `fixType` = 3D, `gnssFixOK` set

On the OpenDragy USB serial console (after flashing product firmware): look for `src=PVT` and rising `pvt=` counts.

---

## Why not 25 Hz on MG-A01?

MG-A01 is an M10 Ultra rated for **10 Hz** with up to 32 satellites. Pushing higher rates on M10 typically cuts the satellite budget. Dragy Pro markets up to 25 Hz on its hardware; for this module, **10 Hz PVT + multi-GNSS + SBAS** is the accuracy-first choice.

---

## App aiding (no u-center)

On BLE connect the Flutter app injects:

1. **UBX-MGA-INI-TIME_UTC** — phone UTC, ~1 s accuracy, trusted flag  
2. **UBX-MGA-INI-POS_LLH** — phone GNSS/network position when available; otherwise last saved OpenDragy fix  

Grant location permission for best cold-start behaviour.

---

## Legacy NMEA note

Older OpenDragy builds used GGA+RMC over BLE. Current firmware uses binary **ODGP** packets derived from NAV-PVT. The Flutter app still accepts legacy NMEA if an old firmware is flashed.
