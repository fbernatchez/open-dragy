# 🏁 OpenDragy

OpenDragy is a high-precision, open-source vehicle performance timer that measures acceleration, speed intervals, and distances. It combines custom **ESP32-S3 firmware** reading a 10Hz GPS and a BMI160 accelerometer with a sleek, dark-themed **Flutter companion app** over Bluetooth Low Energy (BLE).

---

## ✨ Features

* **High-Precision Telemetry (10Hz)**: Receives and parses binary **UBX-NAV-PVT** packets from the u-blox GPS module 10 times per second, providing precise speed, position, and satellite count directly from the chip's internal navigation solution.
* **Real-Time G-Force Telemetry**: Streams live accelerometer data at 20Hz from the onboard BMI160 IMU for instant G-force mapping and post-run acceleration curve analysis.
* **Zero-Crossing Interpolation**: Interpolates the exact start time (down to the millisecond) between the last stationary tick and the first launch tick, guaranteeing highly accurate launch timings.
* **Auto-Armed Launch Control**: Automatically starts recording when speed exceeds `3.0 km/h` to bypass GPS drift/wandering, auto-stops when stationary, and auto-disarms upon completion.
* **Wakelock Integration**: Intelligently keeps your device screen awake and active during armed and ongoing runs, so you never miss your telemetry.
* **Aesthetic Companion App**: Built with Flutter featuring a premium OLED black design with Neon Amber and Neon Green styling, utilizing the Inter font family.
* **Garage & Fleet Management**: Track multiple vehicles locally and link performance runs to specific cars or bikes.
* **Automated Weather Logging**: Uses coordinates from the GPS at the time of the run to fetch ambient temperature, altitude, and relative humidity from the free Open-Meteo API.
* **Run Database & Analytics**: View historical runs with detailed interactive charts showing speed curves, G-force mapping, and elevation/slope profiles to ensure valid runs.

---

## 🏎️ Supported Run Types & Targets

### Drag Mode (From a standstill)
* **Distances**: 60ft, 330ft, 1/8 mile, 1000 ft, 1/4 mile, 1/2 mile (includes trap speed calculations)
* **Speeds**: 0-60 mph, 0-100 km/h, 0-130 mph, 0-200 km/h
* **NHRA Mode**: Optional 1-ft rollout subtraction and 66ft average trap speed calculation to match official track times.

### Interval Mode (Speed-to-Speed)
* **Standard Ranges**:
  * **Imperial**: 0-60 mph, 0-100 mph, 50-75 mph, 60-100 mph, 60-130 mph, 0-130 mph
  * **Metric**: 0-100 km/h, 0-160 km/h, 80-120 km/h, 100-160 km/h, 100-200 km/h, 0-200 km/h
* **Custom Ranges**: Define your own starting and ending speeds (e.g., 100-150 km/h, 80-120 km/h) in both Metric and Imperial units.

---

## 🛠️ Hardware Setup

The hardware unit runs on an **ESP32-S3** microcontroller that interfaces with a high-speed GPS module and a 6-axis IMU sensor.

For a 3D-printable case for the OpenDragy hardware, check out the [OpenDragy Printables page](https://www.printables.com/model/1762658-opendragy-open-source-high-precision-10hz-gps-perf).

### 📋 Bill of Materials (BOM)
1. **ESP32-S3 Mini Development Board** (or similar ESP32-S3 board)
2. **QUESCAN G10A-F30 UBX M10 GPS Module** (supporting 10-25Hz refresh rates and configured at 115200 baud)
3. **BMI160 Accelerometer/Gyroscope IMU Module** (connected via I2C)

### 🔌 Pin Connections
Connect the components to your ESP32-S3 board using the following pin mapping defined in the firmware:

| Component | Component Pin | ESP32-S3 Pin | Notes |
| :--- | :--- | :--- | :--- |
| **BMI160 IMU** | VCC | 3.3V | Power supply |
| | GND | GND | Ground |
| | SDA | **GPIO 1** | I2C Data line |
| | SCL | **GPIO 2** | I2C Clock line |
| **u-blox GPS** | VCC | 3.3V or 5V | Power supply (depending on module) |
| | GND | GND | Ground |
| | TX | **GPIO 4** | Connects to ESP32-S3 RX (UART1) |
| | RX | **GPIO 5** | Connects to ESP32-S3 TX (UART1) |

---

## 💾 Firmware Installation

The ESP32-S3 firmware is located in [`OpenDragy.ino`](OpenDragy.ino).

1. Install the Arduino IDE or VS Code with the PlatformIO extension.
2. Install the **ESP32 board support package** if using Arduino IDE.
3. Install the library dependencies:
   * **DFRobot_BMI160** library (for interfacing with the IMU)
   * **BLE** stack (built-in for ESP32/ESP32-S3)
4. Open [`OpenDragy.ino`](OpenDragy.ino).
5. Compile and flash the code to your ESP32-S3.
6. The device will boot and start broadcasting a BLE service named `OpenDragy`.

---

## 📱 Mobile App Setup

The companion application is written in Flutter and is located in the root directory.

### Prerequisites
* Flutter SDK (v3.11.5 or newer recommended)
* Android Studio (for Android build) / Xcode (for iOS build, macOS required)
* A physical device with Bluetooth enabled (BLE is not supported on most simulators/emulators)

### Getting Started

1. Get packages and dependencies:
   ```bash
   flutter pub get
   ```

2. Run the application on a connected device:
   ```bash
   flutter run --release
   ```
   *(Running in release mode is recommended for accurate performance and UI timing).*

---

## 📂 Code Structure

* [`OpenDragy.ino`](OpenDragy.ino): Microcontroller C++ firmware for reading binary UBX-NAV-PVT packets over UART & I2C IMU data and transmitting over BLE.
* [`lib/main.dart`](lib/main.dart): Main application entry point, sets up global theme and screen routing.
* [`lib/services/physics_engine.dart`](lib/services/physics_engine.dart): Advanced physics computations (trapezoidal integration, zero-crossing interpolation, speed interval timing).
* [`lib/services/ble_service.dart`](lib/services/ble_service.dart): BLE scanner and stream listener that parses binary UBX packets & IMU data.
* [`lib/providers/dragy_provider.dart`](lib/providers/dragy_provider.dart): Core state provider coordinating Bluetooth events, GPS/IMU data processing, runs logic, settings, and database saves.
* [`lib/services/history_service.dart`](lib/services/history_service.dart): Manages local saving and retrieval of historical run logs.
* [`lib/services/weather_service.dart`](lib/services/weather_service.dart): Integration with Open-Meteo API to log run-time environment data.
* [`lib/services/garage_service.dart`](lib/services/garage_service.dart): Manages local storage of vehicle profiles (cars, bikes) for fleet management.
* [`lib/services/settings_service.dart`](lib/services/settings_service.dart): Handles user preferences such as unit toggles (Metric/Imperial) and app settings.
* [`lib/screens/dashboard_screen.dart`](lib/screens/dashboard_screen.dart): Live telemetry display, speedometer, Bluetooth controls, and active timer stats.
* [`lib/screens/run_history_screen.dart`](lib/screens/run_history_screen.dart): Displays the history of all recorded runs and allows filtering or selecting runs to view details.
* [`lib/screens/run_detail_screen.dart`](lib/screens/run_detail_screen.dart): Post-run analysis, graphs, G-force curves, and slope validations.
* [`lib/screens/garage_screen.dart`](lib/screens/garage_screen.dart): Interface for adding, editing, and selecting vehicles.
* [`lib/screens/settings_screen.dart`](lib/screens/settings_screen.dart): UI for configuring app preferences.