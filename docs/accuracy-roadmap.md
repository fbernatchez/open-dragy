# OpenDragy – roadmap přesnosti a validace

Tento dokument popisuje pořadí prací nutných k tomu, aby výsledky OpenDragy
byly reprodukovatelné, auditovatelné a použitelné pro porovnávání performance
dílů. Nové funkce, zejména IMU fusion a statistické porovnávání jízd, se mají
stavět až nad ověřeným GPS výpočtem.

## Hlavní pravidla

- Surová data jsou zdroj pravdy a nesmí se přepisovat.
- Každá uložená jízda musí uvádět verzi aplikace, firmwaru, protokolu a
  výpočetního algoritmu.
- Stejná surová data musí při stejné verzi algoritmu vždy vytvořit stejný
  výsledek.
- Neplatný nebo chybějící vzorek nesmí potichu změnit časovou základnu.
- Kvalita jízdy musí být součástí výsledku, ne pouze informační badge.
- Fused výsledek nesmí být označen jako oficiální, dokud nebude validován proti
  referenčnímu měření.

## Potvrzené kritické problémy

### P0.1 – Outlier rejection posouvá GPS čas

Stav: opraveno v `algorithmVersion = 2`. IMU-dependentní outlier filtr byl
z oficiální GPS cesty odstraněn. Časový stav nyní rozlišuje poslední viděnou
a poslední přijatou `iTOW`; odmítnutá duplicita ani paket mimo pořadí stav
výpočtu nezmění.

`PhysicsEngine.updateMetrics()` aktualizuje `_lastGpsTimeMs` a
`_lastGpsTimeSeconds` před rozhodnutím outlier filtru. Když filtr vzorek
odmítne a vrátí původní stav, čas odmítnutého vzorku již zůstane uložený.

Důsledky:

- část elapsed time se ztratí;
- část vzdálenosti se nezaintegruje;
- další vzorek používá příliš krátké `dt`;
- výsledný čas může vyjít systematicky rychlejší.

Požadovaná oprava:

- rozlišit `lastSeenGpsTime` a `lastAcceptedGpsTime`;
- stav výpočtu commitnout až po přijetí vzorku;
- odmítnutí vzorku nesmí zahodit skutečný čas mezi posledním přijatým a
  následujícím přijatým vzorkem.

### P0.2 – Neplatný GPS fix může vstoupit do fyziky

Stav: opraveno v `algorithmVersion = 2`. Raw zachycení proběhne před quality
gate a nese explicitní příznak `valid`. Do fyziky se pustí pouze validní 3D
NAV-PVT fix s alespoň čtyřmi satelity.

V `_onOdgpFix()` se rychlost zpracuje při podmínce odpovídající
`fix.valid || fix.speedKmh >= 0`. Protože běžná rychlost je nezáporná, může tato
podmínka obejít kontrolu `fix.valid`.

Požadovaná oprava:

- všechny pakety zachovat v raw logu;
- do měřicího výpočtu pustit jen povolený typ validního fixu;
- samostatně kontrolovat `gnssFixOK`, `fixType`, PVT původ a přesnost;
- odmítnutí zaznamenat v diagnostice jízdy.

### P0.3 – Duplicity, pakety mimo pořadí a mezery

Stav: základní klasifikace implementována v `GpsEpochClassifier`. Duplicity a
pakety mimo pořadí se nezapočítají, rollover je povolen pouze u hranice GPS
týdne a mezera používá svůj skutečný časový rozdíl. Počítadla a finální
quality gate pro mezery zůstávají ve Fázi 3.

Neplatné `dt` může ponechat poslední platnou hodnotu a vzorek se přesto
zaintegruje. Každý záporný rozdíl `iTOW` je navíc považován za rollover GPS
týdne.

Požadované chování:

- stejné `iTOW`: označit jako duplicitu a nezapočítat;
- malé záporné `iTOW`: označit jako paket mimo pořadí a nezapočítat;
- rollover uznat pouze poblíž skutečné hranice GPS týdne;
- mezeru evidovat a podle délky snížit důvěryhodnost nebo jízdu zneplatnit;
- nikdy potichu nenahradit neznámé `dt` poslední známou hodnotou.

### P0.4 – IMU nemá vlastní přesný čas

Stav: bezpečná část opravy dokončena. IMU již neposouvá start, neodmítá GPS
rychlost a nemá tick-based časový posun závislý na GPS rate. Zůstává pouze
diagnostickou hodnotou G a raw streamem do zavedení timestampů ODGP v2.

IMU vzorku je nyní přiřazen poslední známý GPS `iTOW`. Více IMU vzorků tak může
mít stejný nebo zastaralý GPS čas. Současný fused start proto nemůže poskytovat
deklarovanou přesnost IMU.

Do zavedení ESP timestampů:

- používat GPS start jako oficiální výsledek;
- IMU start zobrazovat pouze diagnosticky, nebo jeho korekci vypnout;
- neoznačovat takový výsledek jako přesnější fused měření.

## Fáze 0 – Uchování dat a verzování

- [ ] Zachovat existující raw záznamy beze změny.
- [x] Zavést `algorithmVersion`.
- [ ] Ukládat verzi aplikace, ESP firmwaru a ODGP protokolu.
- [x] Označit historické výsledky verzí algoritmu, která je vytvořila.
- [ ] Umožnit pozdější přepočet staré jízdy bez změny původního raw logu.

Výstupní podmínka: ze saved run lze zjistit, jakým kódem byl výsledek vypočten.

## Fáze 1 – Referenční offline výpočet

Vytvořit čistý výpočetní modul:

```text
raw samples
  → validace a řazení epoch
  → accepted sample stream
  → detekce startu
  → integrace
  → interpolace milníků
  → výsledek a quality report
```

Modul nesmí záviset na UI, BLE callbacku, času telefonu ani mutable stavu
provideru.

### Povinné testy

- [ ] Konstantní rychlost.
- [ ] Konstantní zrychlení.
- [ ] Chybějící jeden GPS paket.
- [ ] Několik chybějících paketů.
- [x] Duplicitní `iTOW`.
- [x] Paket mimo pořadí.
- [x] Neplatný fix uprostřed jízdy.
- [x] GPS week rollover.
- [ ] Mezery 0,2 s, 0,5 s a 2 s.
- [ ] Jednorázový speed outlier.
- [ ] Více po sobě jdoucích outlierů.
- [ ] Přesná interpolace 0–100 km/h.
- [ ] Přesná interpolace 60 ft, 1/8 mile a 1/4 mile.
- [ ] Replay skutečných jízd stažených z telefonu.

### Invarianty

- Odmítnutý vzorek nesmí zkrátit elapsed time.
- Duplicitní vzorek nesmí změnit výsledek.
- Paket mimo pořadí nesmí být integrován jako nový vzorek.
- Elapsed time musí odpovídat rozdílu přijatých časových epoch.
- Vzdálenost se integruje pouze mezi platnými přijatými epochami.
- Opakovaný replay musí vytvořit totožný výsledek.

Výstupní podmínka: všechny syntetické i golden replay testy procházejí.

## Fáze 2 – GPS state machine

Zavést jedno místo, které každý GPS paket klasifikuje:

```text
accepted
duplicate
out_of_order
invalid_fix
accuracy_rejected
gap
```

Pouze `accepted` smí změnit:

- poslední přijatou epochu;
- aktuální rychlost;
- elapsed time;
- vzdálenost;
- historii a milníky.

Outlier filtr má být nejprve konzervativní a GPS-only. Závislost na ručně
orientované IMU se vrátí až po vyřešení orientace a synchronizace času.

Výstupní podmínka: online výpočet a offline replay dávají stejný výsledek.

## Fáze 3 – Validita a quality report

Každá jízda musí skončit jedním ze stavů:

```text
valid_for_comparison
valid_orientation_only
invalid
```

Quality report má obsahovat alespoň:

- přijatý a očekávaný počet 10Hz GPS epoch;
- počet duplicit, paketů mimo pořadí a odmítnutých fixů;
- nejdelší mezeru;
- `fixType` a `gnssFixOK`;
- podíl PVT vzorků;
- maximum nebo 95. percentil `hAcc` a `sAcc`;
- minimum nebo percentil počtu satelitů;
- sklon a změnu nadmořské výšky;
- důvod případného zneplatnění.

Průměrné a minimální `hAcc` nestačí, protože mohou skrýt krátký kritický úsek.

Výstupní podmínka: neúplná nebo nekvalitní jízda nemůže být omylem použita do
produktového porovnání.

## Fáze 4 – ODGP v2 a IMU transport

### GPS frame

- [ ] `sequence`.
- [ ] GPS `iTOW`.
- [ ] `espReceiveTimestampUs`.
- [ ] validity flags.
- [ ] stav fronty a kumulativní drop counter.

### IMU frame

- [ ] Binární accel+gyro.
- [ ] Timestamp každého vzorku nebo base timestamp + `dt`.
- [ ] BMI160 FIFO nebo data-ready interrupt.
- [ ] 100Hz skutečné vzorkování.
- [ ] Dávka pěti vzorků v jedné BLE notifikaci.
- [ ] Sequence a detekce chybějící dávky.

BLE může zůstat přibližně na 20 stabilních notifikacích za sekundu. Každá
notifikace ponese pět 100Hz IMU vzorků.

Výstupní podmínka: telefon prokazatelně obdrží nebo identifikuje ztrátu každého
100Hz IMU vzorku.

## Fáze 5 – Fused start na ESP32

ESP32 bude držet 2–3sekundový pre-launch ring buffer. GPS potvrdí skutečný
pohyb a firmware se následně vrátí v IMU bufferu k trvalému počátku
akcelerace.

Po dobu validace ukládat paralelně:

```text
gpsStartTime
imuCandidateTime
fusedStartTime
launchSource
confidence
decisionReason
```

Telefon musí nadále uložit surová GPS i IMU data. ESP výsledek nesmí být jediný
zdroj.

Výstupní podmínka: fused start nemá proti referenci systematický bias a splňuje
předem definované limity opakovatelnosti.

## Fáze 6 – Automatická orientace

- [ ] 6osý quaternion filtr z accel+gyro.
- [ ] Klidová kalibrace gravitace.
- [ ] Automatické určení dopředné osy při přímém rozjezdu.
- [ ] Určení znaménka osy podle růstu GPS rychlosti.
- [ ] Detekce posunutí zařízení během jízdy.
- [ ] `orientationQuality`.
- [ ] Automatický fallback na GPS-only při nízké kvalitě.

Magnetometr nepoužívat jako hlavní referenci bez samostatné validace na motorce
a v autě.

## Fáze 7 – Validace měřicího systému

Provádět souběžná měření:

- OpenDragy;
- komerční Dragy nebo přesnější reference;
- vysokorychlostní video;
- několik opakování stejné konfigurace.

Předem stanovit akceptační limity:

- maximální povolený systematický bias;
- 95% limit rozdílu startu a cílových časů;
- povolenou citlivost na orientaci zařízení;
- požadovanou detekci chybějících paketů;
- podmínky automatického zneplatnění jízdy.

## Fáze 8 – Porovnávání performance dílů

Do porovnání přijímat pouze `valid_for_comparison` jízdy.

Zaznamenat a kontrolovat:

- vozidlo, konfiguraci a verzi dílu;
- jezdce a hmotnost;
- palivo;
- teplotu motoru;
- tlak a teplotu pneumatik podle potřeby;
- počasí;
- směr a úsek;
- sklon;
- pořadí jízd a změny podmínek.

Výsledky uvádět jako:

- počet validních jízd A/B;
- medián;
- rozdíl mediánů;
- procentuální rozdíl;
- interval nejistoty;
- 0–100 km/h, 1/8 mile, 1/4 mile a trap speed odděleně.

Jedna nejlepší jízda A proti jedné nejlepší jízdě B není dostatečný podklad pro
produktové tvrzení.

## Doporučené pořadí implementace

1. Opravit P0.1 až P0.4.
2. Zavést offline calculation core a replay testy.
3. Zavést GPS state machine a quality report.
4. Ověřit nové výsledky na existujících raw datech.
5. Implementovat ODGP v2, sequence a ESP timestampy.
6. Přenášet 100Hz IMU v 20Hz BLE dávkách.
7. Přidat diagnostický fused start.
8. Přidat automatickou orientaci.
9. Validovat proti referenci.
10. Teprve poté stavět statistické porovnání dílů a produktová tvrzení.

## Referenční poznatky z oficiálních aplikací Dragy

Statický rozbor aplikací Dragy 2.22.2, Dragy OBD 2.30 a Dragy·Lap 1.140.1 je
zapsán v [dragy-reference-analysis.md](dragy-reference-analysis.md).

Nejdůležitější dopady na tento plán:

- nalezená Android výpočetní cesta je GPS-only; IMU fusion proto není nutná
  podmínka pro první přesnou a auditovatelnou verzi;
- Dragy podporuje 10, 20 a 25Hz GPS, používá `iTOW` a interpolaci milníků;
- ztracené epochy eviduje a může kvůli nim jízdu zneplatnit;
- kvalitu hodnotí také přes DOP, C/N0 nejsilnějších satelitů a sklon;
- 1-foot rollout je samostatná výpočetní veličina;
- firmware zařízení nebyl v APK, takže případnou pomocnou interní práci s IMU
  nelze tímto rozborem potvrdit ani vyloučit.

Do Fáze 3 proto doplnit NAV-SAT/C/N0 a rate-normalizované limity ztrát. Před
Fází 4 ověřit maximální stabilní GPS rate konkrétního u-blox modulu a nastavení
konstelací. Vyšší počet zobrazených desetinných míst po interpolaci se nesmí
zaměnit za validovanou fyzikální přesnost.

## Aktuální nejbližší krok

Vytvořit čistý offline replay core a golden testy nad skutečnými raw jízdami.
Doplnit počítadla klasifikací a quality report; `gap` zatím výpočet rozpozná,
ale uloženou jízdu ještě automaticky nezneplatní. Neměnit oficiální GPS start
na ESP/fused a nemíchat tuto změnu s novým BLE protokolem.
