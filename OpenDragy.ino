#include <Arduino.h>
#include <math.h>
#include <string.h>
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
BLECharacteristic *pRcGpsMain = NULL;
BLECharacteristic *pRcGpsTime = NULL;
BLE2902 *pTxCccd = NULL;
BLE2902 *pImuCccd = NULL;
BLE2902 *pRcGpsMainCccd = NULL;
BLE2902 *pRcGpsTimeCccd = NULL;

volatile bool deviceConnected = false;
volatile bool oldDeviceConnected = false;
bool imuReady = false;

#define SERVICE_UUID "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID_RX "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID_TX "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID_IMU "6e400004-b5a3-f393-e0a9-e50e24dcca9e"

// RaceChrono DIY BLE GPS — https://github.com/aollin/racechrono-ble-diy-device
static const uint16_t kRcServiceUuid = 0x1FF8;
static const uint16_t kRcGpsMainUuid = 0x0003;
static const uint16_t kRcGpsTimeUuid = 0x0004;

unsigned long lastImuTime = 0;
const int imuInterval = 50;

struct GnssFix {
  bool valid = false;
  double latitude = 0;
  double longitude = 0;
  double altitudeM = 0;
  double speedKmh = 0;
  double headingDeg = 0;
  double hdop = 99;
  uint8_t fixQuality = 0;
  uint8_t satellites = 0;
  int year = 2000; // full year
  int month = 1;
  int day = 1;
  int hour = 0;
  int minute = 0;
  int second = 0;
  int millisecond = 0;
};

GnssFix gFix;
int gRcPrevDateAndHour = -1;
uint8_t gRcSyncBits = 0;
unsigned long gLastRcNotifyMs = 0;
const unsigned long kRcNotifyIntervalMs = 100; // ~10 Hz

static bool notifyEnabled(BLE2902 *cccd) {
  return cccd != nullptr && cccd->getNotifications();
}

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) {
    deviceConnected = true;
    pServer->updateConnParams(pServer->getConnId(), 0x06, 0x12, 0, 100);
    Serial.println("[BLE] Client connected");
  }
  void onDisconnect(BLEServer *pServer) {
    deviceConnected = false;
    Serial.println("[BLE] Client disconnected");
  }
};

class MyCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    // Binary-safe: UBX aiding frames contain 0x00 (do not use c_str()).
    uint8_t *data = pCharacteristic->getData();
    size_t len = pCharacteristic->getLength();
    if (data != nullptr && len > 0) {
      UART.write(data, len);
    }
  }
};

static bool parseCoord(const char *field, char hemi, double &outDeg) {
  if (!field || !*field) {
    return false;
  }
  const int hemiLen = (hemi == 'E' || hemi == 'W') ? 3 : 2;
  const size_t len = strlen(field);
  if ((int)len <= hemiLen) {
    return false;
  }
  char degPart[4] = {0};
  memcpy(degPart, field, hemiLen);
  const double deg = atof(degPart);
  const double min = atof(field + hemiLen);
  double val = deg + min / 60.0;
  if (hemi == 'S' || hemi == 'W') {
    val = -val;
  }
  outDeg = val;
  return true;
}

static void parseNmeaTime(const char *field) {
  if (!field || strlen(field) < 6) {
    return;
  }
  char buf[16];
  strncpy(buf, field, sizeof(buf) - 1);
  buf[sizeof(buf) - 1] = '\0';
  // HHMMSS.sss
  char hh[3] = {buf[0], buf[1], 0};
  char mm[3] = {buf[2], buf[3], 0};
  char ss[3] = {buf[4], buf[5], 0};
  gFix.hour = atoi(hh);
  gFix.minute = atoi(mm);
  gFix.second = atoi(ss);
  gFix.millisecond = 0;
  const char *dot = strchr(buf, '.');
  if (dot && strlen(dot + 1) > 0) {
    // fractional seconds → ms (up to 3 digits)
    double frac = atof(dot);
    gFix.millisecond = (int)llround(frac * 1000.0);
    if (gFix.millisecond < 0) {
      gFix.millisecond = 0;
    }
    if (gFix.millisecond > 999) {
      gFix.millisecond = 999;
    }
  }
}

static void parseNmeaDate(const char *field) {
  // DDMMYY
  if (!field || strlen(field) < 6) {
    return;
  }
  char dd[3] = {field[0], field[1], 0};
  char mo[3] = {field[2], field[3], 0};
  char yy[3] = {field[4], field[5], 0};
  gFix.day = atoi(dd);
  gFix.month = atoi(mo);
  gFix.year = 2000 + atoi(yy);
}

static void parseNmeaLine(const char *line) {
  if (strncmp(line, "$GNRMC", 6) != 0 && strncmp(line, "$GPRMC", 6) != 0 &&
      strncmp(line, "$GNGGA", 6) != 0 && strncmp(line, "$GPGGA", 6) != 0) {
    return;
  }

  char buf[160];
  strncpy(buf, line, sizeof(buf) - 1);
  buf[sizeof(buf) - 1] = '\0';
  char *star = strchr(buf, '*');
  if (star) {
    *star = '\0';
  }

  char *fields[24] = {0};
  int count = 0;
  char *tok = strtok(buf, ",");
  while (tok && count < 24) {
    fields[count++] = tok;
    tok = strtok(nullptr, ",");
  }

  if (strncmp(line + 3, "RMC", 3) == 0) {
    if (count < 10) {
      return;
    }
    parseNmeaTime(fields[1]);
    const bool active = fields[2] && fields[2][0] == 'A';
    if (!active) {
      gFix.valid = false;
      gFix.fixQuality = 0;
      gFix.speedKmh = 0;
      return;
    }
    parseCoord(fields[3], fields[4] ? fields[4][0] : 'N', gFix.latitude);
    parseCoord(fields[5], fields[6] ? fields[6][0] : 'E', gFix.longitude);
    const double knots = fields[7] ? atof(fields[7]) : 0;
    gFix.speedKmh = knots * 1.852;
    gFix.headingDeg = fields[8] ? atof(fields[8]) : 0;
    parseNmeaDate(fields[9]);
    gFix.valid = true;
    if (gFix.fixQuality == 0) {
      gFix.fixQuality = 1;
    }
    return;
  }

  if (strncmp(line + 3, "GGA", 3) == 0) {
    if (count < 10) {
      return;
    }
    parseNmeaTime(fields[1]);
    parseCoord(fields[2], fields[3] ? fields[3][0] : 'N', gFix.latitude);
    parseCoord(fields[4], fields[5] ? fields[5][0] : 'E', gFix.longitude);
    gFix.fixQuality = fields[6] ? (uint8_t)atoi(fields[6]) : 0;
    gFix.satellites = fields[7] ? (uint8_t)atoi(fields[7]) : 0;
    gFix.hdop = fields[8] ? atof(fields[8]) : 99;
    gFix.altitudeM = fields[9] ? atof(fields[9]) : gFix.altitudeM;
    gFix.valid = gFix.fixQuality > 0;
  }
}

// Pack RaceChrono DIY GPS main (20 B) + time (3 B). Big-endian except where noted.
static void packAndNotifyRaceChrono() {
  if (!pRcGpsMain || !notifyEnabled(pRcGpsMainCccd)) {
    return;
  }

  const int dateAndHour = ((gFix.year - 2000) * 8928) + ((gFix.month - 1) * 744) +
                          ((gFix.day - 1) * 24) + gFix.hour;
  if (gRcPrevDateAndHour != dateAndHour) {
    gRcPrevDateAndHour = dateAndHour;
    gRcSyncBits++;
  }

  const int timeSinceHourStart =
      (gFix.minute * 30000) + (gFix.second * 500) + (gFix.millisecond / 2);

  int32_t latitude = 0x7FFFFFFF;
  int32_t longitude = 0x7FFFFFFF;
  if (gFix.valid) {
    latitude = (int32_t)llround(gFix.latitude * 10000000.0);
    longitude = (int32_t)llround(gFix.longitude * 10000000.0);
  }

  uint16_t altitude = 0xFFFF;
  if (gFix.valid) {
    if (gFix.altitudeM > 6000.f) {
      altitude = (uint16_t)(((max(0, (int)lround(gFix.altitudeM + 500.f)) & 0x7FFF) | 0x8000));
    } else {
      altitude =
          (uint16_t)(max(0, (int)lround((gFix.altitudeM + 500.f) * 10.f)) & 0x7FFF);
    }
  }

  uint16_t speed = 0xFFFF;
  if (gFix.valid) {
    if (gFix.speedKmh > 600.f) {
      speed = (uint16_t)(((max(0, (int)lround(gFix.speedKmh * 10.f)) & 0x7FFF) | 0x8000));
    } else {
      speed = (uint16_t)(max(0, (int)lround(gFix.speedKmh * 100.f)) & 0x7FFF);
    }
  }

  // COG from NMEA is garbage when nearly stopped — DIY invalid is 0xFFFF.
  static const double kMinBearingSpeedKmh = 2.0;
  uint16_t bearing = 0xFFFF;
  if (gFix.valid && gFix.speedKmh >= kMinBearingSpeedKmh) {
    double hdg = fmod(gFix.headingDeg, 360.0);
    if (hdg < 0) {
      hdg += 360.0;
    }
    bearing = (uint16_t)lround(hdg * 100.0);
    if (bearing > 35999) {
      bearing = 0;
    }
  }

  uint8_t hdopByte = 0xFF;
  if (gFix.valid && gFix.hdop < 25.5) {
    hdopByte = (uint8_t)min(255, (int)lround(gFix.hdop * 10.f));
  }

  const uint8_t fixQ = (uint8_t)min(0x3, (int)gFix.fixQuality);
  const uint8_t sats = gFix.valid ? (uint8_t)min(0x3F, (int)gFix.satellites) : 0x3F;

  uint8_t mainData[20];
  mainData[0] = (uint8_t)(((gRcSyncBits & 0x7) << 5) | ((timeSinceHourStart >> 16) & 0x1F));
  mainData[1] = (uint8_t)(timeSinceHourStart >> 8);
  mainData[2] = (uint8_t)timeSinceHourStart;
  mainData[3] = (uint8_t)((fixQ << 6) | (sats & 0x3F));
  mainData[4] = (uint8_t)(latitude >> 24);
  mainData[5] = (uint8_t)(latitude >> 16);
  mainData[6] = (uint8_t)(latitude >> 8);
  mainData[7] = (uint8_t)latitude;
  mainData[8] = (uint8_t)(longitude >> 24);
  mainData[9] = (uint8_t)(longitude >> 16);
  mainData[10] = (uint8_t)(longitude >> 8);
  mainData[11] = (uint8_t)longitude;
  mainData[12] = (uint8_t)(altitude >> 8);
  mainData[13] = (uint8_t)altitude;
  mainData[14] = (uint8_t)(speed >> 8);
  mainData[15] = (uint8_t)speed;
  mainData[16] = (uint8_t)(bearing >> 8);
  mainData[17] = (uint8_t)bearing;
  mainData[18] = hdopByte;
  mainData[19] = 0xFF; // VDOP unimplemented

  pRcGpsMain->setValue(mainData, 20);
  pRcGpsMain->notify();

  if (pRcGpsTime) {
    uint8_t timeData[3];
    timeData[0] = (uint8_t)(((gRcSyncBits & 0x7) << 5) | ((dateAndHour >> 16) & 0x1F));
    timeData[1] = (uint8_t)(dateAndHour >> 8);
    timeData[2] = (uint8_t)dateAndHour;
    pRcGpsTime->setValue(timeData, 3);
    if (notifyEnabled(pRcGpsTimeCccd)) {
      pRcGpsTime->notify();
    }
  }
}

void setupBLE() {
  BLEDevice::init("OpenDragy");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // --- OpenDragy Nordic UART ---
  BLEService *pService = pServer->createService(SERVICE_UUID);

  pTxCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_TX, BLECharacteristic::PROPERTY_NOTIFY);
  pTxCccd = new BLE2902();
  pTxCharacteristic->addDescriptor(pTxCccd);

  pImuCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_IMU, BLECharacteristic::PROPERTY_NOTIFY);
  pImuCccd = new BLE2902();
  pImuCharacteristic->addDescriptor(pImuCccd);

  BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_RX, BLECharacteristic::PROPERTY_WRITE);
  pRxCharacteristic->setCallbacks(new MyCallbacks());

  pService->start();

  // --- RaceChrono DIY GPS ---
  BLEService *rcService = pServer->createService(kRcServiceUuid);
  pRcGpsMain = rcService->createCharacteristic(
      kRcGpsMainUuid, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pRcGpsMainCccd = new BLE2902();
  pRcGpsMain->addDescriptor(pRcGpsMainCccd);

  pRcGpsTime = rcService->createCharacteristic(
      kRcGpsTimeUuid, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pRcGpsTimeCccd = new BLE2902();
  pRcGpsTime->addDescriptor(pRcGpsTimeCccd);
  rcService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->addServiceUUID(kRcServiceUuid);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("[BLE] Advertising OpenDragy (NUS) + RaceChrono DIY (0x1FF8)");
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
    // Drop UBX replies (ACK/NAK after CFG) so they don't corrupt NMEA lines.
    static uint8_t ubxState = 0; // 0=NMEA, 1=got 0xB5, 2=reading body
    static uint8_t ubxHdr[4];
    static size_t ubxGot = 0;
    static size_t ubxNeed = 0;

    const bool nusTxOn = notifyEnabled(pTxCccd);
    const bool imuOn = notifyEnabled(pImuCccd);
    const bool rcOn = notifyEnabled(pRcGpsMainCccd);

    while (UART.available() > 0) {
      uint8_t c = (uint8_t)UART.read();

      if (ubxState == 1) {
        if (c == 0x62) {
          ubxState = 2;
          ubxGot = 0;
          ubxNeed = 0;
        } else {
          ubxState = 0;
        }
        continue;
      }

      if (ubxState == 2) {
        if (ubxGot < 4) {
          ubxHdr[ubxGot++] = c;
          if (ubxGot == 4) {
            uint16_t len = (uint16_t)ubxHdr[2] | ((uint16_t)ubxHdr[3] << 8);
            ubxNeed = 4 + len + 2; // class,id,len,payload,ckA,ckB
            if (ubxNeed > 4096) {
              ubxState = 0; // absurd length — resync
            }
          }
        } else {
          ubxGot++;
          if (ubxGot >= ubxNeed) {
            ubxState = 0;
          }
        }
        continue;
      }

      // Start of a UBX frame while idle NMEA buffer.
      if (gpsBufIndex == 0 && c == 0xB5) {
        ubxState = 1;
        continue;
      }

      if (gpsBufIndex < sizeof(gpsBuffer) - 1) {
        gpsBuffer[gpsBufIndex++] = (char)c;
      }
      if (c == '\n' || gpsBufIndex >= 200) {
        if (gpsBufIndex > 1 && gpsBuffer[0] == '$') {
          // Always parse for RaceChrono DIY packing.
          gpsBuffer[gpsBufIndex] = '\0';
          parseNmeaLine(gpsBuffer);

          // OpenDragy app: forward raw NMEA when subscribed.
          if (nusTxOn && pTxCharacteristic) {
            pTxCharacteristic->setValue((uint8_t *)gpsBuffer, gpsBufIndex);
            pTxCharacteristic->notify();
          }
        }
        gpsBufIndex = 0;
      }
    }

    if (rcOn) {
      const unsigned long now = millis();
      if (now - gLastRcNotifyMs >= kRcNotifyIntervalMs) {
        gLastRcNotifyMs = now;
        packAndNotifyRaceChrono();
      }
    }

    if (imuReady && imuOn && pImuCharacteristic) {
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
