#include <Arduino.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <DFRobot_BMI160.h>
#include <HardwareSerial.h>
#include <Wire.h>

HardwareSerial UART(1);
DFRobot_BMI160 bmi160;

BLEServer *pServer = NULL;
BLECharacteristic *pTxCharacteristic = NULL;
BLECharacteristic *pImuCharacteristic = NULL;

volatile bool deviceConnected = false;
volatile bool oldDeviceConnected = false;
bool imuReady = false;

#define SERVICE_UUID "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID_RX "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID_TX "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID_IMU "6e400004-b5a3-f393-e0a9-e50e24dcca9e"

unsigned long lastImuTime = 0;
const int imuInterval = 50;

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

void setupBLE() {
  BLEDevice::init("OpenDragy");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *pService = pServer->createService(SERVICE_UUID);

  pTxCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_TX, BLECharacteristic::PROPERTY_NOTIFY);
  pTxCharacteristic->addDescriptor(new BLE2902());

  pImuCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_IMU, BLECharacteristic::PROPERTY_NOTIFY);
  pImuCharacteristic->addDescriptor(new BLE2902());

  BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_RX, BLECharacteristic::PROPERTY_WRITE);
  pRxCharacteristic->setCallbacks(new MyCallbacks());

  pService->start();
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();
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

  Serial.println("Starting GPS UART1 interface...");
  UART.setRxBufferSize(1024);
  UART.begin(115200, SERIAL_8N1, 4, 5);
  delay(100);

  Serial.println("Initializing BLE Stack...");
  setupBLE();

  Serial.println("=== SYSTEM READY: Awaiting BLE connection ===");
}

void loop() {
  if (deviceConnected) {
    static char gpsBuffer[256];
    static size_t gpsBufIndex = 0;

    while (UART.available() > 0) {
      char c = UART.read();
      if (gpsBufIndex < sizeof(gpsBuffer) - 1) {
        gpsBuffer[gpsBufIndex++] = c;
      }
      if (c == '\n' || gpsBufIndex >= 200) {
        pTxCharacteristic->setValue((uint8_t *)gpsBuffer, gpsBufIndex);
        pTxCharacteristic->notify();
        gpsBufIndex = 0;
      }
    }

    if (imuReady) {
      unsigned long currentMillis = millis();
      if (currentMillis - lastImuTime >= imuInterval) {
        lastImuTime = currentMillis;
        int16_t accelGyro[6] = {0};
        bmi160.getAccelGyroData(accelGyro);

        char imuData[32];
        snprintf(imuData, sizeof(imuData), "%d,%d,%d\n", accelGyro[3],
                 accelGyro[4], accelGyro[5]);
        pImuCharacteristic->setValue((uint8_t *)imuData, strlen(imuData));
        pImuCharacteristic->notify();
      }
    }
  }

  if (!deviceConnected && oldDeviceConnected) {
    delay(500);
    pServer->getAdvertising()->start();
    oldDeviceConnected = false;
  }
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = true;
  }
}