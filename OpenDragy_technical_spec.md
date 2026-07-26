# OpenDragy — Technická specifikace SW/FW architektury

> Plánovací dokument pro IDE. Navazuje na `OpenDragy_backlog.md`.
>
> **Stav (2026-07):** Produktový firmware posílá přes Nordic UART binární **ODGP** (z UBX-NAV-PVT), ne NMEA.
> Sekce o **RaceChrono DIY (0x1FF8)** níže je historický / nerealizovaný plán — v aktuálním
> `OpenDragy.ino` **není**. Pro pravdu o chování viz `README.md` a kód.

---

## 1. BLE architektura — dvojitá GATT služba

### Princip
Jeden GATT server (ESP32-S3). Dříve plánované dvě služby současně; **shipped** je jen služba A
(OpenDragy NUS). Routing notifikací řeší CCCD subscribe.

### Služba A — OpenDragy vlastní protokol (aktuální)
```
SERVICE_UUID           6e400001-b5a3-f393-e0a9-e50e24dcca9e
CHARACTERISTIC_TX      6e400003-...  (NOTIFY)  — ODGP binary GPS fix (~10 Hz)
CHARACTERISTIC_RX      6e400002-...  (WRITE)   — passthrough do GPS UART (aiding / CFG)
CHARACTERISTIC_IMU     6e400004-...  (NOTIFY)  — IMU X,Y,Z csv
```

### Služba B — RaceChrono DIY BLE API (NENÍ v aktuálním FW)
```
SERVICE_UUID            0x1FF8  (00001ff8-0000-1000-8000-00805f9b34fb)
GPS_MAIN                0x0003  (READ + NOTIFY)
GPS_TIME                0x0004  (READ + NOTIFY)
CANBUS_MAIN             0x0001  (READ + NOTIFY)  — plán: G-force jako custom PID
CANBUS_FILTER           0x0002  (WRITE)
```


### Advertising
Přidat OBĚ service UUID do advertisement packetu (`pAdvertising->addServiceUUID()` 2×),
ať obě appky zařízení najdou při scanu. Žádný vliv na chování po připojení.

### Firmware loop — princip (pseudokód)
```cpp
void loop() {
  readSensors();               // GPS UBX-NAV-PVT parse, IMU read — vždy, nezávisle na BLE

  if (subscribed(OPENDRAGY_TX))     notifyOpenDragyPacket();
  if (subscribed(RACECHRONO_GPS))   notifyRaceChronoGpsPacket();
  if (subscribed(RACECHRONO_CAN))   notifyRaceChronoCanPacket(gForceAsPid);

  flushRingBufferToSdIfDue();  // nezávisle na BLE, viz sekce 4
}
```
`subscribed(x)` = dotaz na CCCD stav dané charakteristiky (NimBLE to trackuje samo,
netřeba vlastní stavový flag — ale lze si ho cachovat v `onSubscribe` callbacku
kvůli přehlednosti kódu).

### Otevřené otázky k ověření na HW
- [ ] RAM dopad při 2 současných BLE spojeních (RaceChrono + OpenDragy na 2 telefonech zároveň) — jen pokud by k tomu časem došlo
- [ ] Bandwidth: notify do 2 center současně při 10Hz — otestovat výpadky/zpoždění

---

## 2. Datové formáty

### RaceChrono GPS main (0x0003) — 20 bajtů, big-endian
| bajty | obsah |
|---|---|
| 0-2 | sync bits (3b) + čas od začátku hodiny (21b) |
| 3 | fix quality (2b) + satelity (6b) |
| 4-7 | lat × 10 000 000, int32 — **shodné rozlišení s UBX-NAV-PVT!** |
| 8-11 | lon × 10 000 000, int32 |
| 12-13 | altitude (viz spec, 2 varianty enkódování dle rozsahu) |
| 14-15 | speed (km/h × 100, 2 varianty dle rozsahu) |
| 16-17 | bearing × 100 |
| 18 | HDOP × 10 |
| 19 | VDOP × 10 |

### RaceChrono GPS time (0x0004) — 3 bajty
sync bits + (rok-2000)*8928 + (měsíc-1)*744 + (den-1)*24 + hodina

**Sync bits mezi 0x0003 a 0x0004 musí sedět** — appka na ně čeká při párování dvou charakteristik.

### RaceChrono CAN-Bus main (0x0001) — pro G-force
```
byte 0-3   32-bit packet ID (little-endian!, pozor na rozdíl od zbytku spec)
byte 4-19  payload (1-16 B) — sem G-force jako float/int32 dle zvolené PID konvence
```

### UBX-NAV-PVT — klíčová pole k parsování (firmware, #F2)
```
lat, lon      int32, 1e-7 deg     → přímo kopírovatelné do RaceChrono formátu
height        int32, mm
hAcc, vAcc    uint32, mm          → nahrazuje dnešní HDOP-based gate
gSpeed        int32, mm/s
headMot       int32, 1e-5 deg
```

### OpenDragy interní binární log (SD karta, #F1)
```
uint32  timestamp_ms     4 B
float32 lat, lon, alt    12 B
float32 speedKmh         4 B
int16   accel_x,y,z      6 B
= 26 B / vzorek, 4h @ 10Hz ≈ 6-8 MB
```

---

## 3. Pin mapa (ESP32-S3-Zero)

| Funkce | GPIO | Poznámka |
|---|---|---|
| I2C SDA (IMU BMI160) | 1 | sdílet i s MAX17048 fuel gauge (#H2), jiná adresa |
| I2C SCL | 2 | |
| UART1 RX (GPS) | 4 | |
| UART1 TX (GPS) | 5 | |
| SD SPI CS | 10 | |
| SD SPI MOSI | 11 | |
| SD SPI SCK | 12 | |
| SD SPI MISO | 13 | |
| Status WS2812 | 18 | nový, oddělený od onboard LED |
| Onboard WS2812 (heartbeat) | 21 | already fixed on board |

**Nepoužívat:** GPIO0 (boot), GPIO19/20 (USB), GPIO33-37 (nevyvedené), GPIO43/44 (UART0/debug), GPIO45/46 (strapping)

**PSRAM:** Arduino IDE → Tools → PSRAM → **QSPI PSRAM** (ne OPI — deska má quad-mode 2MB PSRAM)

---

## 4. Navrhovaná struktura firmware souborů

```
OpenDragy.ino                  — setup()/loop(), orchestrace
ble_opendragy_service.h/.cpp   — služba A (stávající UART protokol)
ble_racechrono_service.h/.cpp  — služba B (0x1FF8), packet builders
gps_ubx_parser.h/.cpp          — NAV-PVT binary parsing (#F2)
imu_driver.h/.cpp              — BMI160, 3-osé čtení
sd_logger.h/.cpp               — ring buffer (RAM/PSRAM) + periodický flush (#F1)
power_monitor.h/.cpp           — MAX17048 fuel gauge (#H2)
status_led.h/.cpp              — WS2812 stavový model (#H3)
config.h                       — piny, konstanty, thresholdy (jedno místo pravdy)
```

`config.h` je důležitý — sem patří `launchCommitThreshold` a podobné konstanty,
i když launch detekci na firmwaru neděláme (#15/#F3 zrušeno), aby se předešlo
budoucímu rozjetí hodnot mezi Dart (`physics_engine.dart`) a C++, pokud by se
k firmware-side detekci časem přesto přistoupilo.

---

## 5. Mobilní appka — maximalizace raw dat, rekonstrukce orientace, korelace počasí

Princip celé sekce: appka je **primární zdroj pravdy**. Ukládá se maximum syrových dat
u každého běhu, veškeré dopočítávání (orientace, korelace počasí) běží v appce hned po
běhu a výsledek se ukládá SPOLU s daty. PC/Python dostává při exportu už hotová obohacená
data — nemusí nic přepočítávat, jen agreguje napříč běhy/sessions (viz sekce 6).

### 5.1 Rozšířený `DataPoint` (navazuje na #A5)
Dnešní `DataPoint` nese jen zpracované/projektované hodnoty. Cíl: nic raw nezahazovat.
```dart
class DataPoint {
  final double elapsedTime;
  final double speedKmh;
  final double? altitude;
  final double? lat, lon;                         // NOVÉ — per-bod pozice (dnes jen na úrovni SavedRun/žádná)
  final double? hAcc, vAcc;                        // NOVÉ — z UBX-NAV-PVT (#F2), přesnější než jen HDOP na úrovni běhu
  final double rawAccelX, rawAccelY, rawAccelZ;    // NOVÉ — nekalibrovaná, neprojektovaná IMU data
  final double gForce;                             // dopočítáno POST-RUN (5.3), pole zůstává pro zpětnou kompatibilitu UI
}
```
Firmware syrové osy i UBX pole už má/bude mít (#F2) — jde jen o to je poslat přes BLE a
v appce neukázat, ale ULOŽIT. Přenosová/úložná režie navíc je zanedbatelná v poměru k
hodnotě dat pro pozdější podrobnou PC analýzu.

### 5.2 Rozšířený `SavedRun` — persistované diagnostiky a počasí
```dart
class SavedRun {
  ...
  final double? densityAltitude;         // NOVÉ — spočteno jednou po běhu, uloženo (ne jen live v _EnvironmentCard)
  final String? calibratedAxis;          // NOVÉ — "x"/"y"/"z"/"-x"... diagnostika z 5.3
  final double? axisCorrelationR2;       // NOVÉ — jak spolehlivá byla volba osy (viz 5.3, krok 3)
}
```
Účel: i syrová diagnostika kalibrace se ukládá, ne jen výsledek — na PC pak jde zpětně
ověřit/zpochybnit, jestli appka vybrala osu správně, bez nutnosti mít znovu k dispozici
telefon nebo přepočítávat od nuly.

### 5.3 Rekonstrukce orientace akcelerometru (post-run, ne live autokalibrace)
Live autokalibrace (za běhu) je zbytečně riskantní přesně v okamžiku launche, kdy na
přesnosti nejvíc záleží, a nepatří na firmware (princip "firmware = jen sběr dat").
Řešení: dopočítat až po ukončení běhu nad celou `history`.

1. **Gravitační vektor** — průměr X/Y/Z ze vzorků PŘED launchem (klidová fáze, dnes už
   dostupná v `_preRunBuffer`/historii před triggerem).
2. **Odečtení gravitace** — zůstává zrychlení jen v horizontální rovině zařízení (2 osy).
3. **Určení podélné osy** — korelace GPS-odvozeného zrychlení (derivace `speedKmh`) proti
   oběma zbylým osám přes celý běh. Nejvyšší korelace = podélná osa, znaménko = směr.
   → `axisCorrelationR2` z 5.2 se ukládá přímo odsud.
4. **Rekonstrukce G-force** — projekce na určenou osu se správným znaménkem → `gForce`
   pole, beze změny navazuje na `TelemetryChartPainter`/`_smoothList`.
5. *(Budoucí)* — zbylá osa po odečtení gravitace a podélné složky = boční G (zatáčky),
   zajímavé až pro okreskový use case.

Implementace: nová funkce vedle `PhysicsEngine`, volaná jednou po `isRunning → false`,
ne v hot-path.

**Otevřené otázky:** minimální délka klidové fáze pro spolehlivý odhad gravitace; fallback
při nejednoznačné korelaci obou os (např. montáž přesně na 45°) — možná ukázat uživateli
varování s `axisCorrelationR2` místo tichého (možná špatného) výběru.

### 5.4 Korelace počasí — kalibrace přímo v appce (revize `#A8`)
**Změna oproti dřívější úvaze:** regrese se počítá v appce, ne v Pythonu. Appka ukládá
kalibraci přímo k datům (bod uživatele), Python ji jen čte/zobrazuje/případně zpřesňuje.

```dart
class WeatherCalibration {
  final String vehicleId;
  final String testCategoryId;   // regrese per test kategorie (0-60mph, 1/4mile...), ne jen jedna globální
  final double slope;             // změna ET na metr DA
  final double intercept;
  final double rSquared;
  final int sampleCount;
  final DateTime lastUpdated;
}
```
- Nová Hive box `calibration_box`, klíč `"$vehicleId:$testCategoryId"`.
- Jednoduchá lineární regrese (least squares) čistě v Dart — netřeba externí balíček,
  jde o pár řádků (`slope`, `intercept`, `R²` ze standardních vzorců).
- Přepočet: po každém novém uloženém běhu se stejným `vehicleId`, nad všemi historickými
  běhy dané kategorie (počet vzorků je malý, i o desítkách/stovkách běhů je to okamžité,
  netřeba inkrementální algoritmus).
- `densityAltitude` (5.2) je vstup regrese, `SavedRun.temperature`/`humidity` už existují.
- **Gating na spolehlivost:** pokud `sampleCount` < práh (např. 5) nebo `rSquared` nízké,
  korekce se v UI ukazuje jako "nekalibrováno / nespolehlivé", raw čas zůstává primární.
- Korigovaný čas se dopočítává on-the-fly z uloženého `slope`/`intercept` při zobrazení
  (ne přepočítávat historii při každé aktualizaci koeficientu) — konzistentní se zásadou
  "raw data se nikdy nepřepisují".

---

## 6. Desktop aplikace (Python) — architektura

Navazuje na `#P1`/`#P2`/`#A8` z backlogu. Tři moduly, dá se stavět nezávisle na sobě.

### 6.1 Modul: A/B Analyzer (`#P1`)
```
analyzer/
  load.py       — načtení JSON exportů (#A2), parsování do DataFrame
  stats.py      — Mann-Whitney U, mean/median/improvement % (viz ukázka dřív v konverzaci)
  report.py     — formátovaný výstup (Stock/Prototype/improvement/confidence)
```

### 6.2 Modul: Korelace počasí (`#A8`) — REVIDOVÁNO, appka je autoritativní
**Změna:** appka (5.4) teď sama počítá i ukládá `WeatherCalibration` přímo k datům.
Export (`#A2`) obsahuje jak surová data (DA, ET), tak už hotový koeficient appky.
Python modul je nyní **sekundární/kontrolní nástroj**, ne zdroj pravdy:
```
weather/
  crosscheck.py   — nezávislý přepočet regrese nad exportovanými DA/ET (scipy.stats.linregress),
                    porovnání s koeficientem uloženým appkou — odhalí případný rozdíl/chybu v Dart výpočtu
  visualize.py    — scatter plot DA vs ET s proloženou přímkou, pro vizuální kontrolu odlehlých hodnot
```
Užitečné hlavně jako **nezávislá kontrola appky** (dva nezávislé výpočty stejné věci by
měly sedět) a pro pokročilejší analýzy, které appka neumí (např. porovnání koeficientů
napříč víc vozidly najednou, hledání vzorců v tom, jak moc je které auto citlivé na DA).
Není to ale nutná závislost pro běžné každodenní použití appky.

### 6.3 Modul: Mapové okno (`#P2`)
```
mapview/
  app.py         — Dash entry point, layout 50/50 (mapa | tabulka+grafy)
  map_panel.py   — dash-leaflet nebo Scattermapbox, overlay 2 tras (červená/modrá)
  compare_panel.py — matplotlib/plotly grafy (speed/time, G-force/speed), tabulka diff
```
Vyžaduje `lat`/`lon` v `history` bodech exportu — závisí na dokončení práce z bodu 5
výše (rozšíření `DataPoint`) a na `#A2` export update.

### 6.4 Modul: MoTeC export (`#P3`, budoucí, nízká priorita)
Jen jako doplněk k vizuálnímu prohlížení jedné jízdy — neduplikovat A/B analýzu do MoTeC.

### Sdílené závislosti
```
pandas, scipy, matplotlib   — analyzer + weather
dash, dash-leaflet, plotly  — mapview (samostatný, těžší dependency, ať nejde do analyzeru)
```
Doporučeno jako 2 samostatné vstupní body (`analyzer/` spustitelný bez Dash závislostí),
ne jedna monolitická appka — analyzer budeš používat mnohem častěji než mapu.

---

## 7. Návaznosti mezi položkami backlogu

```
#F2 (UBX-NAV-PVT) ──┬──▶ #A3 (RaceChrono BLE)
                     └──▶ zpřesnění GPS gate v appce

#F1 (SD ring buffer) ──▶ #A1 (autonomní nahrávání) ──▶ #A2 (export)

#H2 (18650 + fuel gauge) ──▶ #A11 (baterie v UI)

#A5 (raw 3-osý IMU + lat/lon/hAcc/vAcc v DataPoint, 5.1) ──▶ 5.3 (post-run rekonstrukce G-force)
                                                          └──▶ nahrazuje dnešní pevnou Y-osu v `dragy_provider.dart`

#A2 (export s lat/lon) ──▶ #P2 (mapové okno)
#A2 (export s project/config/session) ──▶ #P1 (Python A/B analyzer)

5.4 (appka počítá WeatherCalibration) ──▶ #A2 export (koeficient + raw DA/ET) ──▶ 6.2 Python crosscheck (volitelné)
```
