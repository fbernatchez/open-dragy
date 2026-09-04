#include <Arduino.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <DFRobot_BMI160.h>
#include <HardwareSerial.h>
#include <Update.h>
#include <Wire.h>

HardwareSerial UART(1);
DFRobot_BMI160 bmi160;

BLEServer *pServer = NULL;
BLECharacteristic *pTxCharacteristic = NULL;
BLECharacteristic *pImuCharacteristic = NULL;

volatile bool deviceConnected = false;
volatile bool oldDeviceConnected = false;
bool imuReady = false;
bool otaRebootPending = false;

#define SERVICE_UUID "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID_RX "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID_TX "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID_IMU "6e400004-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID_VERSION "6e400005-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID_OTA_CTRL "6e400006-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID_OTA_DATA "6e400007-b5a3-f393-e0a9-e50e24dcca9e"

#define FIRMWARE_VERSION "1.0.2"

// RTOS Queue for GPS packets
QueueHandle_t gpsQueue;

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) {
    deviceConnected = true;
    pServer->updateConnParams(pServer->getConnId(), 0x06, 0x12, 0, 100);
  };
  void onDisconnect(BLEServer *pServer) { deviceConnected = false; }
};

class MyCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    String rxValue = pCharacteristic->getValue();
    if (rxValue.length() > 0) {
      UART.write((uint8_t *)rxValue.c_str(), rxValue.length());
    }
  }
};

class OtaCtrlCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    String rxValue = pCharacteristic->getValue();
    if (rxValue.length() > 0) {
      uint8_t cmd = rxValue[0];
      if (cmd == 0x00) { // Start OTA
        if (rxValue.length() >= 5) {
          uint32_t fwSize = rxValue[1] | (rxValue[2] << 8) |
                            (rxValue[3] << 16) | (rxValue[4] << 24);
          Serial.printf("OTA Start, size: %d\n", fwSize);
          if (!Update.begin(fwSize, U_FLASH)) {
            Serial.println("OTA Update.begin failed");
          }
        }
      } else if (cmd == 0x01) { // End OTA
        Serial.println("OTA End");
        if (Update.end(true)) {
          Serial.println("OTA Success! Rebooting...");
          otaRebootPending = true;
        } else {
          Serial.printf("OTA Error: %s\n", Update.errorString());
        }
      }
    }
  }
};

class OtaDataCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    String rxValue = pCharacteristic->getValue();
    if (rxValue.length() > 0) {
      if (Update.write((uint8_t *)rxValue.c_str(), rxValue.length()) !=
          rxValue.length()) {
        Serial.println("OTA Write failed");
      }
    }
  }
};

void setupBLE() {
  BLEDevice::init("OpenDragy");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *pService = pServer->createService(SERVICE_UUID);

  BLECharacteristic *pVersionCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_VERSION, BLECharacteristic::PROPERTY_READ);
  pVersionCharacteristic->setValue(FIRMWARE_VERSION);

  pTxCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_TX, BLECharacteristic::PROPERTY_NOTIFY);
  pTxCharacteristic->addDescriptor(new BLE2902());

  pImuCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_IMU, BLECharacteristic::PROPERTY_NOTIFY);
  pImuCharacteristic->addDescriptor(new BLE2902());

  BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_RX, BLECharacteristic::PROPERTY_WRITE);
  pRxCharacteristic->setCallbacks(new MyCallbacks());

  BLECharacteristic *pOtaCtrlCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_OTA_CTRL, BLECharacteristic::PROPERTY_WRITE);
  pOtaCtrlCharacteristic->setCallbacks(new OtaCtrlCallbacks());

  BLECharacteristic *pOtaDataCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_OTA_DATA,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  pOtaDataCharacteristic->setCallbacks(new OtaDataCallbacks());

  pService->start();
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();
}

// Function to send a formatted UBX packet
void sendUBX(uint8_t cls, uint8_t id, const uint8_t *payload, uint16_t len) {
  UART.write(0xB5);
  UART.write(0x62);
  UART.write(cls);
  UART.write(id);
  UART.write(len & 0xFF);
  UART.write((len >> 8) & 0xFF);

  uint8_t ck_a = 0, ck_b = 0;
  ck_a += cls;
  ck_b += ck_a;
  ck_a += id;
  ck_b += ck_a;
  ck_a += (len & 0xFF);
  ck_b += ck_a;
  ck_a += ((len >> 8) & 0xFF);
  ck_b += ck_a;

  for (uint16_t i = 0; i < len; i++) {
    UART.write(payload[i]);
    ck_a += payload[i];
    ck_b += ck_a;
  }
  UART.write(ck_a);
  UART.write(ck_b);
}

void setupGPS() {
  Serial.println("Configuring u-blox GPS (Auto-baud & UBX NAV-PVT)...");

  // Connect at default u-blox baud rate to send configuration
  UART.begin(38400, SERIAL_8N1, 4, 5);
  delay(200);

  // CFG-VALSET Payload for u-blox M10 (Layer 1 = RAM)
  // 1. CFG-UART1-BAUDRATE = 115200 (0x0001C200) -> Key: 0x40520001
  uint8_t baudPayload[] = {
      0x00, 0x01, 0x00, 0x00, // Version 0, Layer 1 (RAM), Reserved
      0x01, 0x00, 0x52, 0x40, // Key: CFG-UART1-BAUDRATE
      0x00, 0xC2, 0x01, 0x00  // Value: 115200
  };
  sendUBX(0x06, 0x8A, baudPayload, sizeof(baudPayload));
  delay(100);

  // Switch ESP32 UART to the new 115200 baud
  UART.end();
  UART.begin(115200, SERIAL_8N1, 4, 5);
  delay(200);

  // 2. CFG-RATE-MEAS = 100ms (10Hz) -> Key: 0x30210001
  // 3. CFG-NAVSPG-DYNMODEL = 4 (Automotive) -> Key: 0x20110021
  // 4. CFG-MSGOUT-UBX_NAV_PVT_UART1 = 1 -> Key: 0x20910007
  // 5. Disable NMEA outputs on UART1
  uint8_t configPayload[] = {
      0x00, 0x01, 0x00, 0x00, // Version 0, Layer 1 (RAM), Reserved

      0x01, 0x00, 0x21, 0x30, // Key: CFG-RATE-MEAS
      0x64, 0x00,             // Value: 100ms

      0x21, 0x00, 0x11, 0x20, // Key: CFG-NAVSPG-DYNMODEL
      0x04,                   // Value: Automotive

      0x07, 0x00, 0x91, 0x20, // Key: CFG-MSGOUT-UBX_NAV_PVT_UART1
      0x01,                   // Value: 1 (Enable)

      0xBA, 0x00, 0x91, 0x20, // Key: CFG-MSGOUT-NMEA_ID_GGA_UART1
      0x00,                   // Value: 0 (Disable)

      0xC9, 0x00, 0x91, 0x20, // Key: CFG-MSGOUT-NMEA_ID_GLL_UART1
      0x00,

      0xC0, 0x00, 0x91, 0x20, // Key: CFG-MSGOUT-NMEA_ID_GSA_UART1
      0x00,

      0xC5, 0x00, 0x91, 0x20, // Key: CFG-MSGOUT-NMEA_ID_GSV_UART1
      0x00,

      0xAC, 0x00, 0x91, 0x20, // Key: CFG-MSGOUT-NMEA_ID_RMC_UART1
      0x00,

      0xB1, 0x00, 0x91, 0x20, // Key: CFG-MSGOUT-NMEA_ID_VTG_UART1
      0x00};
  sendUBX(0x06, 0x8A, configPayload, sizeof(configPayload));
  delay(100);

  Serial.println("GPS configuration sent.");
}

// RTOS Task: Read UART and push full UBX packets to Queue
void gpsReadTask(void *parameter) {
  uint8_t buffer[128];
  uint16_t idx = 0;
  uint8_t state = 0;
  uint16_t expectedLen = 0;

  while (1) {
    while (UART.available() > 0) {
      uint8_t c = UART.read();

      switch (state) {
      case 0:
        if (c == 0xB5) {
          buffer[0] = c;
          state = 1;
          idx = 1;
        }
        break;
      case 1:
        if (c == 0x62) {
          buffer[1] = c;
          state = 2;
          idx = 2;
        } else {
          state = 0;
        }
        break;
      case 2: // Class
        buffer[idx++] = c;
        state = 3;
        break;
      case 3: // ID
        buffer[idx++] = c;
        state = 4;
        break;
      case 4: // Length LSB
        buffer[idx++] = c;
        expectedLen = c;
        state = 5;
        break;
      case 5: // Length MSB
        buffer[idx++] = c;
        expectedLen |= (c << 8);
        // NAV-PVT payload is usually 92 or 100 bytes. Reject lengths that are
        // too large.
        if (expectedLen > 110) {
          state = 0;
        } else {
          state = 6;
        }
        break;
      case 6: // Payload
        buffer[idx++] = c;
        if (idx ==
            expectedLen + 6) { // header(2) + cls(1) + id(1) + len(2) + payload
          state = 7;
        }
        break;
      case 7: // Checksum A
        buffer[idx++] = c;
        state = 8;
        break;
      case 8: // Checksum B
        buffer[idx++] = c;

        // Verify Checksum
        uint8_t ck_a = 0, ck_b = 0;
        for (uint16_t i = 2; i < idx - 2; i++) {
          ck_a += buffer[i];
          ck_b += ck_a;
        }

        if (ck_a == buffer[idx - 2] && ck_b == buffer[idx - 1]) {
          // Check if it's NAV-PVT (Class 0x01, ID 0x07)
          if (buffer[2] == 0x01 && buffer[3] == 0x07) {
            // Send to FIFO queue, do not block if full (we drop the oldest or
            // drop this one)
            xQueueSend(gpsQueue, buffer, 0);
          }
        }
        state = 0; // Reset for next packet
        break;
      }
    }
    vTaskDelay(pdMS_TO_TICKS(5)); // Yield to other tasks
  }
}

// RTOS Task: Read from Queue and send BLE Notifications
void bleNotifyTask(void *parameter) {
  uint8_t buffer[128];
  while (1) {
    if (xQueueReceive(gpsQueue, buffer, portMAX_DELAY) == pdTRUE) {
      if (deviceConnected && pTxCharacteristic) {
        uint16_t len = buffer[4] | (buffer[5] << 8);
        uint16_t totalLen =
            len + 8; // Include header, class, id, length, payload, checksum

        // Notify Flutter app
        pTxCharacteristic->setValue(buffer, totalLen);
        pTxCharacteristic->notify();
      }
    }
  }
}

// RTOS Task: IMU polling
void imuTask(void *parameter) {
  while (1) {
    if (deviceConnected && imuReady) {
      int16_t accelGyro[6] = {0};
      bmi160.getAccelGyroData(accelGyro);

      char imuData[32];
      snprintf(imuData, sizeof(imuData), "%d,%d,%d\n", accelGyro[3],
               accelGyro[4], accelGyro[5]);
      pImuCharacteristic->setValue((uint8_t *)imuData, strlen(imuData));
      pImuCharacteristic->notify();
    }
    vTaskDelay(pdMS_TO_TICKS(10)); // 100Hz IMU rate
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("--- OpenDragy Firmware Boot ---");

  Serial.println("Initializing I2C Bus...");
  int attempts = 0;
  int maxAttempts = 3;
  while (attempts < maxAttempts && !imuReady) {
    attempts++;
    Serial.printf("Connecting to BMI160: Attempt %d/%d...\n", attempts,
                  maxAttempts);
    Wire.end();
    Wire.begin(1, 2, 100000);
    delay(50);
    bmi160.softReset();
    delay(100);
    if (bmi160.I2cInit(0x69) == BMI160_OK) {
      Serial.println("-> BMI160 detected and initialized successfully.");
      imuReady = true;
    } else {
      Serial.println("-> Connection failed. Retrying...");
      if (attempts < maxAttempts) {
        delay(200);
      }
    }
  }

  if (!imuReady) {
    Serial.println("[CRITICAL ERROR] BMI160 hardware not responding. Running "
                   "in GPS-only mode.");
  }

  setupGPS();

  Serial.println("Initializing BLE Stack...");
  setupBLE();

  gpsQueue = xQueueCreate(10, 128);

  xTaskCreatePinnedToCore(gpsReadTask, "GPS_Read", 4096, NULL, 2, NULL, 1);
  xTaskCreatePinnedToCore(bleNotifyTask, "BLE_Notify", 4096, NULL, 1, NULL,
                          0); // Run on core 0 with BLE stack
  xTaskCreatePinnedToCore(imuTask, "IMU_Task", 4096, NULL, 1, NULL, 1);

  Serial.println("=== SYSTEM READY: Awaiting BLE connection ===");
}

void loop() {
  if (otaRebootPending) {
    delay(1000);
    ESP.restart();
  }

  if (!deviceConnected && oldDeviceConnected) {
    delay(500);
    pServer->getAdvertising()->start();
    oldDeviceConnected = false;
  }
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = true;
  }
  vTaskDelay(pdMS_TO_TICKS(100)); // Sleep loop task
}