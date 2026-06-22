# OpenDragy - GPS Configuration Guide (u-blox M10)

This document serves as a reference guide to configure a new u-blox M10 GPS module using the **u-center 2** utility to meet the requirements of the OpenDragy firmware.

---

## 🛠️ Step-by-Step Configuration Protocol

### 📄 IMPORTANT: Golden Rule for Saving Settings
In u-center 2, every modification must be explicitly saved to permanent memory. 
Before clicking **Set**, ALWAYS ensure that the following three boxes are checked orange:
* [x] **RAM** (Immediate application)
* [x] **BBR** (Battery-backed RAM backup)
* [x] **Flash** (Permanent on-chip flash backup)

*Do not forget to click the large orange **Send** button in the bottom right corner of the screen after each section to write the physical commands to the GPS module.*

---

## 1. Communication Baudrate
Increase the UART bandwidth to prevent buffer overflow at higher update rates.

* **Section:** `Advanced configuration` -> `CFG-UART1-`
* **Key:** `CFG-UART1-BAUDRATE`
* **Value (raw):** `115200`
* **Action:** Check *RAM, BBR, Flash* -> Click **Set** -> Click **Send**.

⚠️ *Note: As soon as you click Send, u-center 2 will lose the connection. Change the Baudrate of u-center 2 (in the top-left corner of the main window) to **115200** immediately to resume communication.*

---

## 2. Measurement Refresh Rate
Configure the GPS measurement rate to 10 Hz (10 samples per second).

* **Section:** `Advanced configuration` -> `CFG-RATE-`
* **Key:** `CFG-RATE-MEAS`
* **Value (raw):** `100` *(100ms between each measurement = 10Hz)*
* **Action:** Check *RAM, BBR, Flash* -> Click **Set** -> Click **Send**.

---

## 3. NMEA Message Filtering
Disable bulky and unnecessary NMEA sentences to free up the ESP32-S3 UART buffer and optimize Bluetooth stream bandwidth.

* **Section:** `Advanced configuration` -> `CFG-MSGOUT-`

### 🚫 Messages to DISABLE (Value = 0)
* `CFG-MSGOUT-NMEA_ID_GLL_UART1` -> `0`
* `CFG-MSGOUT-NMEA_ID_GSA_UART1` -> `0`
* `CFG-MSGOUT-NMEA_ID_GSV_UART1` -> `0`
* `CFG-MSGOUT-NMEA_ID_VTG_UART1` -> `0`

###  Messages to ENABLE (Value = 1)
* `CFG-MSGOUT-NMEA_ID_GGA_UART1` -> `1` *(Position, Altitude, HDOP)*
* `CFG-MSGOUT-NMEA_ID_RMC_UART1` -> `1` *(Speed and precise Time)*

**Action:** For each key, enter the value, check *RAM, BBR, Flash*, and click **Set**. Once all keys have been updated, click the main **Send** button in the bottom right corner.

