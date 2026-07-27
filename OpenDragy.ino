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

/*
 * OpenDragy firmware — UBX-NAV-PVT path (Dragy-class).
 *
 * GPS (MicoAir MG-A01 / u-blox M10):
 *   - Boot CFG: UBX-only out, NAV-PVT @ 10 Hz, Automotive, multi-GNSS + SBAS (EGNOS in EU)
 *   - BLE NUS TX: compact ODGP binary fix @ ~10 Hz (not NMEA)
 *
 * RaceChrono DIY (0x1FF8) removed — OpenDragy app only.
 */

HardwareSerial UART(1);
DFRobot_BMI160 bmi160;

BLEServer *pServer = NULL;
BLECharacteristic *pTxCharacteristic = NULL;
BLECharacteristic *pImuCharacteristic = NULL;
BLE2902 *pTxCccd = NULL;
BLE2902 *pImuCccd = NULL;

volatile bool deviceConnected = false;
volatile bool oldDeviceConnected = false;
bool imuReady = false;

#define SERVICE_UUID "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID_RX "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID_TX "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID_IMU "6e400004-b5a3-f393-e0a9-e50e24dcca9e"

unsigned long lastImuTime = 0;
unsigned long lastImuSampleMs = 0;
/** BMI160 stays at 100 Hz ODR + on-chip LPF; we boxcar-average into BLE. */
const int imuSampleIntervalMs = 10; // read chip ~100 Hz
const int imuInterval = 50;         // notify ~20 Hz over BLE (phone rarely keeps >20–25)
long imuAccSum[3] = {0, 0, 0};
int imuAccCount = 0;
unsigned long lastOdgpNotifyMs = 0;
/** Min gap between ODGP notifies; <100 ms so a short backlog can catch up. */
const unsigned long kOdgpMinIntervalMs = 50;

// Small ODGP TX ring — absorbs BLE stalls (e.g. phone A2DP music) without dropping iTOW ticks.
static const size_t kOdgpQueueCap = 16;
static uint8_t odgpQueue[kOdgpQueueCap][52];
static uint8_t odgpQHead = 0;
static uint8_t odgpQTail = 0;
static uint8_t odgpQCount = 0;
static uint32_t gOdgpEnqueued = 0;
static uint32_t gOdgpSent = 0;
static uint32_t gOdgpDropped = 0;
static uint32_t gImuNotifies = 0;

// --- UBX helpers -----------------------------------------------------------

static void ubxChecksum(const uint8_t *payload, uint16_t len, uint8_t &cka,
                        uint8_t &ckb) {
  cka = 0;
  ckb = 0;
  for (uint16_t i = 0; i < len; i++) {
    cka = (uint8_t)(cka + payload[i]);
    ckb = (uint8_t)(ckb + cka);
  }
}

static void sendUbx(uint8_t cls, uint8_t id, const uint8_t *payload,
                    uint16_t len) {
  uint8_t hdr[4] = {cls, id, (uint8_t)(len & 0xff), (uint8_t)(len >> 8)};
  uint8_t cka = 0, ckb = 0;
  for (int i = 0; i < 4; i++) {
    cka = (uint8_t)(cka + hdr[i]);
    ckb = (uint8_t)(ckb + cka);
  }
  for (uint16_t i = 0; i < len; i++) {
    cka = (uint8_t)(cka + payload[i]);
    ckb = (uint8_t)(ckb + cka);
  }
  UART.write((uint8_t)0xB5);
  UART.write((uint8_t)0x62);
  UART.write(hdr, 4);
  if (len && payload) {
    UART.write(payload, len);
  }
  UART.write(cka);
  UART.write(ckb);
}

/** CFG-VALSET U1 key (little-endian key + 1-byte value). layers: bit0=RAM bit1=BBR bit2=Flash */
static void cfgValSetU1(uint32_t key, uint8_t value, uint8_t layers = 0x07) {
  uint8_t p[9];
  p[0] = 0x00; // version
  p[1] = layers;
  p[2] = 0;
  p[3] = 0;
  p[4] = (uint8_t)(key);
  p[5] = (uint8_t)(key >> 8);
  p[6] = (uint8_t)(key >> 16);
  p[7] = (uint8_t)(key >> 24);
  p[8] = value;
  sendUbx(0x06, 0x8A, p, sizeof(p));
  delay(5);
}

static void cfgValSetU2(uint32_t key, uint16_t value, uint8_t layers = 0x07) {
  uint8_t p[10];
  p[0] = 0x00;
  p[1] = layers;
  p[2] = 0;
  p[3] = 0;
  p[4] = (uint8_t)(key);
  p[5] = (uint8_t)(key >> 8);
  p[6] = (uint8_t)(key >> 16);
  p[7] = (uint8_t)(key >> 24);
  p[8] = (uint8_t)(value);
  p[9] = (uint8_t)(value >> 8);
  sendUbx(0x06, 0x8A, p, sizeof(p));
  delay(5);
}

static void cfgValSetL(uint32_t key, bool on, uint8_t layers = 0x07) {
  cfgValSetU1(key, on ? 1 : 0, layers);
}

static void cfgValSetU4(uint32_t key, uint32_t value, uint8_t layers = 0x07) {
  uint8_t p[12];
  p[0] = 0x00;
  p[1] = layers;
  p[2] = 0;
  p[3] = 0;
  p[4] = (uint8_t)(key);
  p[5] = (uint8_t)(key >> 8);
  p[6] = (uint8_t)(key >> 16);
  p[7] = (uint8_t)(key >> 24);
  p[8] = (uint8_t)(value);
  p[9] = (uint8_t)(value >> 8);
  p[10] = (uint8_t)(value >> 16);
  p[11] = (uint8_t)(value >> 24);
  sendUbx(0x06, 0x8A, p, sizeof(p));
  delay(5);
}

static void enableNavPvtUart1() {
  cfgValSetU1(0x20910007, 1); // CFG-MSGOUT-UBX_NAV_PVT_UART1
  // Legacy CFG-MSG: NAV-PVT on UART1
  uint8_t msg[] = {0x01, 0x07, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00};
  sendUbx(0x06, 0x01, msg, sizeof(msg));
  delay(10);
}

static void configureGpsModule() {
  Serial.println("[GPS] Configuring M10 for NAV-PVT @ 10 Hz (EU multi-GNSS + SBAS)...");

  // Keep BOTH protocols out until PVT is proven — never go silent.
  cfgValSetL(0x10740001, true); // CFG-UART1OUTPROT-UBX
  cfgValSetL(0x10740002, true); // CFG-UART1OUTPROT-NMEA (temp; disable later)
  cfgValSetL(0x10730001, true); // CFG-UART1INPROT-UBX
  cfgValSetL(0x10730002, true); // CFG-UART1INPROT-NMEA

  cfgValSetU2(0x30210001, 100); // 10 Hz
  cfgValSetU2(0x30210002, 1);
  cfgValSetU1(0x20110021, 4); // Automotive

  enableNavPvtUart1();

  // Minimal NMEA fallback (GGA+RMC) so UART is never empty if UBX CFG NAKs
  cfgValSetU1(0x209100ba, 1); // GGA
  cfgValSetU1(0x209100ac, 1); // RMC
  cfgValSetU1(0x209100b1, 0); // VTG off
  cfgValSetU1(0x209100c0, 0); // GSA off
  cfgValSetU1(0x209100c5, 0); // GSV off
  cfgValSetU1(0x209100ca, 0); // GLL off

  // Multi-GNSS + SBAS/EGNOS (Europe)
  cfgValSetL(0x1031001f, true);
  cfgValSetL(0x10310001, true);
  cfgValSetL(0x10310021, true);
  cfgValSetL(0x10310007, true);
  cfgValSetL(0x10310025, true);
  cfgValSetL(0x1031000a, true);
  cfgValSetL(0x10310022, true);
  cfgValSetL(0x1031000d, true);
  cfgValSetL(0x10310020, true);
  cfgValSetL(0x10310005, true);
  cfgValSetL(0x10360002, true);
  cfgValSetL(0x10360004, true);

  Serial.println("[GPS] CFG applied (UBX+NMEA out; will prefer PVT)");
}

/** After we see NAV-PVT, drop NMEA to free UART/BLE bandwidth. */
static void disableNmeaOutputOnce() {
  static bool done = false;
  if (done) return;
  done = true;
  Serial.println("[GPS] PVT locked — disabling NMEA output");
  cfgValSetU1(0x209100ba, 0);
  cfgValSetU1(0x209100ac, 0);
  cfgValSetL(0x10740002, false); // NMEA out off
  enableNavPvtUart1();
}

// --- IMU (BMI160) configuration -----------------------------------------------

/** Configure BMI160 accelerometer to ±8g range (0x08 in ACCEL_RANGE register).
 *  Prevents clipping on hard launches while maintaining sufficient resolution.
 *  Falls back to default 2g if configuration fails.
 */
static bool bmi160WriteReg(uint8_t reg, uint8_t value) {
  Wire.beginTransmission(0x69);
  Wire.write(reg);
  Wire.write(value);
  return Wire.endTransmission() == 0;
}

static bool bmi160ReadReg(uint8_t reg, uint8_t &value) {
  Wire.beginTransmission(0x69);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) {
    return false;
  }
  if (Wire.requestFrom((int)0x69, 1) != 1) {
    return false;
  }
  value = (uint8_t)Wire.read();
  return true;
}

static void configureBmi160AccelRange() {
  if (!imuReady) return;

  // BMI160 register 0x41: ACCEL_RANGE
  // 0x03 = ±2g (default)
  // 0x05 = ±4g
  // 0x08 = ±8g
  // 0x0C = ±16g

  const uint8_t ACCEL_RANGE_REG = 0x41;
  const uint8_t ACCEL_8G = 0x08;

  if (bmi160WriteReg(ACCEL_RANGE_REG, ACCEL_8G)) {
    Serial.println("[IMU] BMI160 accelerometer range set to ±8g");
  } else {
    Serial.println("[IMU] Failed to set ±8g range, using default ±2g");
  }
  delay(10);
}

/** Configure BMI160 accelerometer ODR and on-chip LPF.
 *  ACC_CONF (0x40): acc_odr=100 Hz, acc_bwp=normal (avg4) → ~40 Hz 3 dB BW.
 */
static void configureBmi160AccelFilter() {
  if (!imuReady) return;

  const uint8_t ACC_CONF_REG = 0x40;
  const uint8_t ACC_CONF_100HZ_NORMAL = 0x28; // ODR 0x8 | bwp 0x2 << 4

  if (!bmi160WriteReg(ACC_CONF_REG, ACC_CONF_100HZ_NORMAL)) {
    Serial.println("[IMU] Failed to set ACC_CONF (100 Hz / normal BW)");
    return;
  }

  uint8_t readback = 0;
  if (bmi160ReadReg(ACC_CONF_REG, readback) && readback == ACC_CONF_100HZ_NORMAL) {
    Serial.println("[IMU] BMI160 accel ODR 100 Hz, normal BW (~40 Hz) configured");
  } else {
    Serial.printf("[IMU] ACC_CONF write done, readback=0x%02X\n", readback);
  }
  delay(10);
}

// --- Fix state from NAV-PVT ------------------------------------------------

struct PvtFix {
  bool valid = false;
  uint8_t fixType = 0;
  uint8_t flags = 0;
  uint8_t numSV = 0;
  uint32_t iTOW = 0;
  int32_t lon = 0;     // 1e-7 deg
  int32_t lat = 0;
  int32_t hMSL = 0;    // mm
  int32_t gSpeed = 0;  // mm/s
  int32_t headMot = 0; // 1e-5 deg
  uint32_t hAcc = 0;   // mm
  uint32_t vAcc = 0;   // mm
  uint32_t sAcc = 0;   // mm/s
  uint16_t year = 2000;
  uint8_t month = 1;
  uint8_t day = 1;
  uint8_t hour = 0;
  uint8_t min = 0;
  uint8_t sec = 0;
};

PvtFix gPvt;
bool gPvtFresh = false;
uint32_t gPvtCount = 0;
uint32_t gUbxFrames = 0;
unsigned long gLastGpsStatusMs = 0;

static int32_t rdI32(const uint8_t *p) {
  return (int32_t)((uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
                   ((uint32_t)p[3] << 24));
}
static uint32_t rdU32(const uint8_t *p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
         ((uint32_t)p[3] << 24);
}
static uint16_t rdU16(const uint8_t *p) {
  return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static void wrU16(uint8_t *p, uint16_t v) {
  p[0] = (uint8_t)v;
  p[1] = (uint8_t)(v >> 8);
}
static void wrI32(uint8_t *p, int32_t v) {
  uint32_t u = (uint32_t)v;
  p[0] = (uint8_t)u;
  p[1] = (uint8_t)(u >> 8);
  p[2] = (uint8_t)(u >> 16);
  p[3] = (uint8_t)(u >> 24);
}
static void wrU32(uint8_t *p, uint32_t v) {
  p[0] = (uint8_t)v;
  p[1] = (uint8_t)(v >> 8);
  p[2] = (uint8_t)(v >> 16);
  p[3] = (uint8_t)(v >> 24);
}

/** NAV-PVT payload is 92 bytes (M10). */
static void parseNavPvt(const uint8_t *p, uint16_t len) {
  if (len < 92) {
    return;
  }
  gPvt.iTOW = rdU32(p + 0);
  gPvt.year = rdU16(p + 4);
  gPvt.month = p[6];
  gPvt.day = p[7];
  gPvt.hour = p[8];
  gPvt.min = p[9];
  gPvt.sec = p[10];
  // p[11] valid flags
  gPvt.fixType = p[20];
  gPvt.flags = p[21];
  gPvt.numSV = p[23];
  gPvt.lon = rdI32(p + 24);
  gPvt.lat = rdI32(p + 28);
  gPvt.hMSL = rdI32(p + 36);
  gPvt.hAcc = rdU32(p + 40);
  gPvt.vAcc = rdU32(p + 44);
  gPvt.gSpeed = rdI32(p + 60);
  gPvt.headMot = rdI32(p + 64);
  gPvt.sAcc = rdU32(p + 68);
  const bool gnssOk = (gPvt.flags & 0x01) != 0;
  gPvt.valid = gnssOk && gPvt.fixType >= 2;
  gPvtFresh = true;
}

static bool gHaveRealPvt = false;
static unsigned long gLastPvtMs = 0;

/**
 * ODGP v1 — 52 bytes little-endian.
 * magic 'ODGP' | ver | fixType | flags | numSV | iTOW | lon | lat | hMSL |
 * gSpeed | headMot | hAcc | vAcc | sAcc | year | month day hour min sec | pad
 * flags: bit0=gnssFixOK, bit1=real NAV-PVT; pad=1 if real PVT.
 */
static void packOdgp(uint8_t *pkt) {
  pkt[0] = 'O';
  pkt[1] = 'D';
  pkt[2] = 'G';
  pkt[3] = 'P';
  pkt[4] = 1; // version
  pkt[5] = gPvt.fixType;
  // App ODGP flags: bit0 = gnssFixOK, bit1 = real NAV-PVT (not NMEA fill).
  pkt[6] = (uint8_t)((gPvt.flags & 0x01) | (gHaveRealPvt ? 0x02 : 0x00));
  pkt[7] = gPvt.numSV;
  wrU32(pkt + 8, gPvt.iTOW);
  wrI32(pkt + 12, gPvt.lon);
  wrI32(pkt + 16, gPvt.lat);
  wrI32(pkt + 20, gPvt.hMSL);
  wrI32(pkt + 24, gPvt.gSpeed);
  wrI32(pkt + 28, gPvt.headMot);
  wrU32(pkt + 32, gPvt.hAcc);
  wrU32(pkt + 36, gPvt.vAcc);
  wrU32(pkt + 40, gPvt.sAcc);
  wrU16(pkt + 44, gPvt.year);
  pkt[46] = gPvt.month;
  pkt[47] = gPvt.day;
  pkt[48] = gPvt.hour;
  pkt[49] = gPvt.min;
  pkt[50] = gPvt.sec;
  pkt[51] = gHaveRealPvt ? 1 : 0;
}

static void enqueueOdgpFromGPvt() {
  uint8_t pkt[52];
  packOdgp(pkt);
  if (odgpQCount >= kOdgpQueueCap) {
    // Drop oldest — prefer fresher fixes when BLE is badly stalled.
    odgpQTail = (uint8_t)((odgpQTail + 1) % kOdgpQueueCap);
    odgpQCount--;
    gOdgpDropped++;
  }
  memcpy(odgpQueue[odgpQHead], pkt, 52);
  odgpQHead = (uint8_t)((odgpQHead + 1) % kOdgpQueueCap);
  odgpQCount++;
  gOdgpEnqueued++;
}

static void drainOdgpQueue() {
  if (odgpQCount == 0 || !pTxCharacteristic || !pTxCccd ||
      !pTxCccd->getNotifications() || !deviceConnected) {
    return;
  }
  const unsigned long now = millis();
  if (lastOdgpNotifyMs != 0 && (now - lastOdgpNotifyMs) < kOdgpMinIntervalMs) {
    return;
  }
  pTxCharacteristic->setValue(odgpQueue[odgpQTail], 52);
  pTxCharacteristic->notify();
  odgpQTail = (uint8_t)((odgpQTail + 1) % kOdgpQueueCap);
  odgpQCount--;
  lastOdgpNotifyMs = now;
  gOdgpSent++;
}

// UBX + NMEA byte pump
static uint8_t ubxBuf[128];
static size_t ubxLen = 0;
static uint8_t ubxState = 0; // 0 idle/NMEA, 1 got B5, 2 collecting UBX
static uint16_t ubxNeed = 0;
static char nmeaBuf[128];
static size_t nmeaLen = 0;
uint32_t gNmeaLines = 0;

static bool parseCoordNmea(const char *field, char hemi, double &outDeg) {
  if (!field || !*field) return false;
  const int hemiLen = (hemi == 'E' || hemi == 'W') ? 3 : 2;
  if ((int)strlen(field) <= hemiLen) return false;
  char degPart[4] = {0};
  memcpy(degPart, field, hemiLen);
  double val = atof(degPart) + atof(field + hemiLen) / 60.0;
  if (hemi == 'S' || hemi == 'W') val = -val;
  outDeg = val;
  return true;
}

/** Fill gPvt from NMEA until real NAV-PVT arrives (hAcc ≈ HDOP×5 m). */
static void parseNmeaLineToPvt(char *line) {
  if (gHaveRealPvt && (millis() - gLastPvtMs) < 2000) {
    return; // prefer fresh UBX
  }
  char *fields[20] = {0};
  int count = 0;
  char *p = line;
  while (*p && count < 20) {
    fields[count++] = p;
    char *c = strchr(p, ',');
    if (!c) break;
    *c = 0;
    p = c + 1;
  }
  if (count < 7) return;

  if (strncmp(line + 3, "RMC", 3) == 0) {
    if (count < 10) return;
    if (fields[1] && strlen(fields[1]) >= 6) {
      char t[16];
      strncpy(t, fields[1], sizeof(t) - 1);
      t[sizeof(t) - 1] = 0;
      char *dot = strchr(t, '.');
      if (dot) *dot = 0;
      if (strlen(t) >= 6) {
        gPvt.hour = (t[0] - '0') * 10 + (t[1] - '0');
        gPvt.min = (t[2] - '0') * 10 + (t[3] - '0');
        gPvt.sec = (t[4] - '0') * 10 + (t[5] - '0');
      }
    }
    const bool active = fields[2] && fields[2][0] == 'A';
    double lat = 0, lon = 0;
    parseCoordNmea(fields[3], fields[4] ? fields[4][0] : 'N', lat);
    parseCoordNmea(fields[5], fields[6] ? fields[6][0] : 'E', lon);
    gPvt.lat = (int32_t)llround(lat * 1e7);
    gPvt.lon = (int32_t)llround(lon * 1e7);
    const double knots = fields[7] ? atof(fields[7]) : 0;
    const double kmh = knots * 1.852;
    gPvt.gSpeed = (int32_t)llround((kmh / 3.6) * 1000.0);
    if (fields[8] && *fields[8]) {
      gPvt.headMot = (int32_t)llround(atof(fields[8]) * 1e5);
    }
    gPvt.valid = active;
    if (active && gPvt.fixType < 2) gPvt.fixType = 2;
    gPvt.flags = active ? 0x01 : 0;
    gPvtFresh = true;
    gNmeaLines++;
    return;
  }

  if (strncmp(line + 3, "GGA", 3) == 0) {
    if (count < 10) return;
    const int q = fields[6] ? atoi(fields[6]) : 0;
    gPvt.numSV = fields[7] ? (uint8_t)atoi(fields[7]) : 0;
    if (q > 0) {
      gPvt.fixType = 3;
      gPvt.flags |= 0x01;
      gPvt.valid = true;
      const double hdop = fields[8] ? atof(fields[8]) : 5.0;
      gPvt.hAcc = (uint32_t)llround(hdop * 5000.0); // mm ≈ HDOP×5 m
      gPvt.vAcc = gPvt.hAcc * 2;
    } else {
      gPvt.fixType = 0;
      gPvt.flags = 0;
      gPvt.valid = false;
      gPvt.hAcc = 0;
      gPvt.vAcc = 0;
    }
    if (fields[9] && *fields[9]) {
      gPvt.hMSL = (int32_t)llround(atof(fields[9]) * 1000.0);
    }
    gPvtFresh = true;
    gNmeaLines++;
  }
}

static void feedGpsByte(uint8_t c) {
  if (ubxState == 1) {
    if (c == 0x62) {
      ubxState = 2;
      ubxLen = 0;
      ubxNeed = 0;
    } else {
      ubxState = (c == 0xB5) ? 1 : 0;
    }
    return;
  }

  if (ubxState == 2) {
    if (ubxLen < sizeof(ubxBuf)) {
      ubxBuf[ubxLen++] = c;
    } else {
      ubxState = 0;
      return;
    }
    if (ubxLen == 4) {
      uint16_t plen = (uint16_t)ubxBuf[2] | ((uint16_t)ubxBuf[3] << 8);
      ubxNeed = 4 + plen + 2;
      if (ubxNeed > sizeof(ubxBuf)) {
        ubxState = 0;
        return;
      }
    }
    if (ubxNeed > 0 && ubxLen >= ubxNeed) {
      const uint8_t cls = ubxBuf[0];
      const uint8_t id = ubxBuf[1];
      const uint16_t plen = (uint16_t)ubxBuf[2] | ((uint16_t)ubxBuf[3] << 8);
      uint8_t cka = 0, ckb = 0;
      ubxChecksum(ubxBuf, 4 + plen, cka, ckb);
      if (cka == ubxBuf[4 + plen] && ckb == ubxBuf[5 + plen]) {
        gUbxFrames++;
        if (cls == 0x01 && id == 0x07) {
          parseNavPvt(ubxBuf + 4, plen);
          gPvtCount++;
          gHaveRealPvt = true;
          gLastPvtMs = millis();
          disableNmeaOutputOnce();
        }
      }
      ubxState = 0;
    }
    return;
  }

  // idle: UBX sync or NMEA line
  if (nmeaLen == 0 && c == 0xB5) {
    ubxState = 1;
    return;
  }

  if (c == '$' || nmeaLen > 0) {
    if (nmeaLen < sizeof(nmeaBuf) - 1) {
      nmeaBuf[nmeaLen++] = (char)c;
    }
    if (c == '\n' || nmeaLen >= sizeof(nmeaBuf) - 1) {
      nmeaBuf[nmeaLen] = 0;
      if (nmeaLen > 6 && nmeaBuf[0] == '$') {
        parseNmeaLineToPvt(nmeaBuf);
      }
      nmeaLen = 0;
    }
  }
}

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
    uint8_t *data = pCharacteristic->getData();
    size_t len = pCharacteristic->getLength();
    if (data != nullptr && len > 0) {
      UART.write(data, len);
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

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("[BLE] Advertising OpenDragy (NUS ODGP + IMU)");
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("--- OpenDragy Firmware Boot (PVT) ---");

  Serial.println("Initializing I2C Bus...");
  int attempts = 0;
  while (attempts < 3 && !imuReady) {
    attempts++;
    Serial.printf("Connecting to BMI160: Attempt %d/3...\n", attempts);
    Wire.end();
    Wire.begin(1, 2, 100000);
    delay(50);
    bmi160.softReset();
    delay(100);
    if (bmi160.I2cInit(0x69) == BMI160_OK) {
      Serial.println("-> BMI160 OK");
      imuReady = true;
      configureBmi160AccelRange();
      configureBmi160AccelFilter();
    } else if (attempts < 3) {
      delay(200);
    }
  }
  if (!imuReady) {
    Serial.println("[WARN] BMI160 missing — GPS-only mode");
  }

  Serial.println("Starting GPS UART1...");
  UART.setRxBufferSize(2048);
  // Try 115200 first (MG-A01 / OpenDragy golden), then 38400 factory.
  UART.begin(115200, SERIAL_8N1, 4, 5);
  delay(300);
  configureGpsModule();

  // If no bytes at all for 1.5 s, retry at 38400 and bump module to 115200.
  {
    unsigned long t0 = millis();
    size_t got = 0;
    while (millis() - t0 < 1500) {
      while (UART.available()) {
        feedGpsByte((uint8_t)UART.read());
        got++;
      }
      delay(5);
    }
    if (got == 0) {
      Serial.println("[GPS] No UART @ 115200 — trying 38400...");
      UART.end();
      delay(50);
      UART.begin(38400, SERIAL_8N1, 4, 5);
      delay(200);
      // Ask module to switch baud (VALSET may still be accepted at 38400).
      cfgValSetU4(0x40520001, 115200); // CFG-UART1-BAUDRATE
      delay(100);
      UART.end();
      delay(50);
      UART.begin(115200, SERIAL_8N1, 4, 5);
      delay(200);
      configureGpsModule();
    } else {
      Serial.printf("[GPS] UART alive (%u bytes in probe)\n", (unsigned)got);
    }
  }

  Serial.println("Initializing BLE...");
  setupBLE();
  Serial.println("=== SYSTEM READY ===");
}

void loop() {
  while (UART.available() > 0) {
    feedGpsByte((uint8_t)UART.read());
  }

  if (gPvtFresh) {
    gPvtFresh = false;
    if (deviceConnected && notifyEnabled(pTxCccd)) {
      enqueueOdgpFromGPvt();
    }
  }
  drainOdgpQueue();

  {
    const unsigned long now = millis();
    if (now - gLastGpsStatusMs >= 1000) {
      gLastGpsStatusMs = now;
      Serial.printf(
          "[GPS] ubx=%lu pvt=%lu nmea=%lu src=%s sv=%u fix=%u hAcc=%.1fm "
          "spd=%.1fkm/h ble=%d odgp q=%u enq=%lu sent=%lu drop=%lu imu=%lu\n",
          (unsigned long)gUbxFrames, (unsigned long)gPvtCount,
          (unsigned long)gNmeaLines, gHaveRealPvt ? "PVT" : "NMEA", gPvt.numSV,
          gPvt.fixType, gPvt.hAcc / 1000.0, (gPvt.gSpeed / 1000.0) * 3.6,
          deviceConnected ? 1 : 0, (unsigned)odgpQCount,
          (unsigned long)gOdgpEnqueued, (unsigned long)gOdgpSent,
          (unsigned long)gOdgpDropped, (unsigned long)gImuNotifies);
      gUbxFrames = 0;
      gPvtCount = 0;
      gNmeaLines = 0;
      gOdgpEnqueued = 0;
      gOdgpSent = 0;
      gOdgpDropped = 0;
      gImuNotifies = 0;
      // Keep asking for NAV-PVT until it sticks.
      if (!gHaveRealPvt) {
        enableNavPvtUart1();
      }
    }
  }

  if (deviceConnected && imuReady && notifyEnabled(pImuCccd) &&
      pImuCharacteristic) {
    unsigned long currentMillis = millis();

    // Sample BMI160 near ODR; accumulate for anti-aliased BLE downsample.
    if (currentMillis - lastImuSampleMs >= (unsigned long)imuSampleIntervalMs) {
      lastImuSampleMs = currentMillis;
      int16_t accelGyro[6] = {0};
      bmi160.getAccelGyroData(accelGyro);
      imuAccSum[0] += accelGyro[3];
      imuAccSum[1] += accelGyro[4];
      imuAccSum[2] += accelGyro[5];
      imuAccCount++;
    }

    if (imuAccCount > 0 &&
        currentMillis - lastImuTime >= (unsigned long)imuInterval) {
      lastImuTime = currentMillis;
      const int16_t ax = (int16_t)(imuAccSum[0] / imuAccCount);
      const int16_t ay = (int16_t)(imuAccSum[1] / imuAccCount);
      const int16_t az = (int16_t)(imuAccSum[2] / imuAccCount);
      imuAccSum[0] = imuAccSum[1] = imuAccSum[2] = 0;
      imuAccCount = 0;

      char imuData[32];
      snprintf(imuData, sizeof(imuData), "%d,%d,%d\n", ax, ay, az);
      pImuCharacteristic->setValue((uint8_t *)imuData, strlen(imuData));
      pImuCharacteristic->notify();
      gImuNotifies++;
    }
  } else {
    // Not subscribed — don't leave a stale accumulator for the next connect.
    imuAccSum[0] = imuAccSum[1] = imuAccSum[2] = 0;
    imuAccCount = 0;
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
