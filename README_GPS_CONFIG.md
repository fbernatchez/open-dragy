# OpenDragy - GPS Configuration Guide (u-blox M10)

This document serves as a reference guide to configure a new u-blox M10 GPS module using the **u-center 2** utility to meet the requirements of the OpenDragy firmware.

---

## 🔌 Prerequisites: Serial Passthrough

To allow the **u-center 2** software on your computer to communicate with the GPS module connected to the ESP32-S3, you must first flash a passthrough sketch.

1. Open `SerialToSerial.ino` in the Arduino IDE. By default, new GPS modules communicate at **38400 baud**. Ensure `GPSSerial.begin()` in the sketch is temporarily changed to **38400** while `Serial.begin()` remains at **115200**.
2. Under the **Tools** menu, ensure your board settings are correct. 
   > [!IMPORTANT]
   > Depending on your specific ESP32-S3 development board (such as the Arduino Nano ESP32), you must change the **Pin Numbering** setting in the Tools menu. Make sure it is set to **"By GPIO number (legacy)"** rather than the default "By Arduino pin (default)". Otherwise, the GPIO 4 and 5 definitions in the sketch will map to incorrect physical pins, and communication will fail.
3. Flash the `SerialToSerial.ino` sketch to your board.
4. Close the Arduino IDE Serial Monitor (so the COM port is free).
5. Open **u-center 2**, click **Add Device**, connect to the COM port of your ESP32-S3, and select **115200 baud** (this is your ESP32 connection speed).

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

> [!WARNING]
> As soon as you click Send, the GPS switches to 115200 baud, but your ESP32 passthrough is still listening at 38400. You will immediately lose connection and start seeing garbage data in u-center 2. This is expected!
> 
> To continue the configuration:
> 1. Go back to the Arduino IDE.
> 2. Change `GPSSerial.begin()` in `SerialToSerial.ino` to **115200**.
> 3. Re-flash the sketch to the ESP32-S3.
> 4. In **u-center 2**, disconnect and reconnect to the COM port at **115200 baud**. You are now ready to continue configuring the GPS!

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

---

## 4. Dynamic Platform Model
Configure the dynamic platform model to optimize the positioning engine for high acceleration environments.

* **Section:** `Advanced configuration` -> `CFG-NAVSPG-`
* **Key:** `CFG-NAVSPG-DYNMODEL`
* **Value:** `4 - AUTOMOT`
* **Action:** Check *RAM, BBR, Flash* -> Click **Set** -> Click **Send**.
