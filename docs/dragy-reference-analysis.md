# Referenční rozbor aplikací Dragy

Datum statického rozboru: 2026-07-28

Analyzované balíčky:

- Dragy 2.22.2
- Dragy 2.30, build 201, vytažený z připojeného telefonu
- Dragy OBD 2.30, build 200 (ARMv7)
- Dragy OBD 2.30, build 202 (ARM64, novější XAPK)
- Dragy·Lap 1.140.1

Balíčky byly rozbaleny a jejich Android bytecode byl dekompilován. Tento
dokument popisuje pouze logiku, kterou lze doložit v aplikacích. Firmware
měřicího zařízení nebyl součástí APK, takže z tohoto rozboru nelze vyloučit
další zpracování uvnitř zařízení.

## Firmware a DFU

Aktuální standardní Dragy 2.30 obsahuje vlastní BLE DFU službu:

- service UUID `00006287-3C17-D293-8E48-14FE2E4DA212`;
- control-point UUID `00006487-3C17-D293-8E48-14FE2E4DA212`;
- metoda `reboot()` zapíše do control pointu příkaz `0x05`.

To dokládá možnost přepnout zařízení do bootloaderu/DFU režimu, ale samo o
sobě nepopisuje formát obrazu, ověření podpisu ani přenosový protokol.

V assetech zůstala stará webová obrazovka aktualizace firmwaru. Volá
`app/C_constant/getCurrentVersion` a umí načíst pole `version.link`, avšak
její download funkce používá natvrdo zadaný historický a nesouvisející Android
APK soubor. Položky této obrazovky jsou navíc v menu zakomentované. Živý pokus
o legacy endpoint skončil HTTP 500, takže z něj nebyl získán firmware ani
platná URL.

Novější XAPK Dragy OBD 2.30 build 202 obsahuje
`resources/assets/obd/CY069_V37_EC25.bin` o velikosti 41 696 bajtů. Jde podle
umístění a názvu o firmware OBD adaptéru, nikoliv standardního měřicího
zařízení Dragy GPS/IMU. Pro standardní Dragy nebyl v APK, split APK, veřejných
souborech telefonu ani dostupném logcatu nalezen firmware image.

Praktická cesta k získání správného obrazu je zachytit skutečnou aktualizační
transakci oficiální aplikace ve chvíli, kdy je připojen originální Dragy a
server mu nabídne update. Odkaz může být odvozený z modelu, sériového čísla a
aktuální verze firmwaru; samotná statická aplikace jej zřejmě neobsahuje.

## Hlavní závěr

V dohledané výpočetní cestě Android aplikace vznikají časy a vzdálenosti z
u-blox GPS zpráv NAV-PVT. Aplikace:

- používá GPS epochy s vlastním časem `iTOW`;
- podporuje konfiguraci GPS na 10, 20 a 25 Hz;
- integruje vzdálenost z GPS ground speed;
- interpoluje překročení rychlosti i vzdálenosti mezi sousedními epochami;
- počítá chybějící epochy a nekvalitní jízdu může zneplatnit;
- hodnotí satelity, DOP, signál a sklon;
- má BLE charakteristiku pro motion data, ale v analyzovaných verzích nebyla
  nalezena její aktivní cesta do výpočtu jízdy.

Pod desetinu sekundy tedy není nutné automaticky vysvětlovat IMU fusion.
20Hz GPS má epochu 50 ms a 25Hz GPS 40 ms. Interpolace poskytne jemnější
číselný výsledek, ale sama o sobě nezaručuje stejně jemnou fyzikální přesnost.

## Míra jistoty

### Potvrzeno v aplikaci

- Příjem a checksum kontrola u-blox NAV-PVT.
- Parsování `iTOW`, fixu, počtu satelitů, polohy, nadmořské výšky, ground
  speed, heading, `hAcc`, `vAcc`, `sAcc`, `headAcc` a `pDOP`.
- GPS konfigurační příkazy pro 10, 20 a 25 Hz.
- Výpočet vzdálenosti lichoběžníkovou integrací GPS rychlosti.
- Lineární časová interpolace rychlostních milníků.
- Kinematická interpolace vzdálenostních milníků při předpokladu konstantního
  zrychlení v intervalu.
- Práh začátku pohybu 0,8 km/h.
- Detekce mezery delší než 0,15 s a evidence chybějících paketů.
- Kontrola kvality pomocí DOP, satelitů, C/N0, ztracených epoch a sklonu.
- Samostatný 1-foot rollout.
- Výpočet zobrazovaného zrychlení/G-force z rozdílu GPS rychlosti, nikoliv z
  nalezeného IMU streamu.

### Silně indikováno, ale ne absolutně potvrzeno

- Oficiální uložené výsledky novějších Lite/Pro zařízení se po stažení
  přepočítávají ze záznamů PVT/SAT/DOP stejným GPS výpočetním jádrem.
- Charakteristika motion data může být nepoužitá, servisní, budoucí nebo určená
  jiné části ekosystému.

### Nelze zjistit z APK

- Zda firmware používá akcelerometr k probuzení, zahájení interního záznamu
  nebo jiné pomocné detekci.
- Přesný firmware sampling, filtrování a časování motion charakteristiky.
- Tovární kalibrace přijímače a antény.
- Laboratorně ověřená absolutní přesnost výsledku.

## GPS protokol a frekvence

Aplikace přijímá binární u-blox NAV-PVT, tedy zprávu třídy `0x01`, ID `0x07`
a payloadem 92 bytů. Před použitím ověřuje UBX checksum.

Z NAV-PVT používá zejména:

- `iTOW` jako časovou osu;
- UTC datum a čas;
- `fixType` a počet satelitů;
- zeměpisnou polohu a nadmořskou výšku;
- horizontální a vertikální přesnost;
- ground speed a její odhad přesnosti;
- heading a jeho přesnost;
- `pDOP`.

NAV-SAT slouží také k odvození průměrného C/N0 čtyř nejsilnějších satelitů.
V aplikaci jsou přítomny UBX konfigurační příkazy pro:

- 10 Hz: perioda 100 ms;
- 20 Hz: perioda 50 ms;
- 25 Hz: perioda 40 ms.

V přiložených testovacích datech Dragy jsou vidět přesné 50ms GPS epochy, tedy
20Hz stream.

To neznamená, že každý u-blox modul nebo každá konstelace zvládne 20/25 Hz.
Pro OpenDragy se musí nejprve ověřit konkrétní modul, firmware GNSS, aktivní
konstelace a skutečný výstupní rate bez vynechaných epoch.

## Detekce startu

Pro start z nuly aplikace hledá přechod přes 0,8 km/h. Nalezená implementace
nastaví základní čas na aktuální GPS epochu. Start je tedy v této cestě
kvantován frekvencí GPS; následné cílové milníky se interpolují.

To je jednodušší než současný zamýšlený fused start OpenDragy, ale má dvě
výhody:

- čas startu i cíle je ve stejné hodinové doméně;
- výsledek není závislý na orientaci ani timestampu IMU.

Pro OpenDragy stojí za otestování dvě GPS-only varianty na stejných raw datech:

1. kompatibilní varianta Dragy s GPS startem při 0,8 km/h;
2. robustní potvrzení rozjezdu například při 3 km/h a zpětná interpolace
   kandidáta přes 0,5 nebo 0,8 km/h.

Druhá varianta může lépe potlačit GPS šum před startem, ale její bias je nutné
změřit proti referenci.

## Rychlostní a vzdálenostní milníky

### Rychlost

Čas překročení cílové rychlosti se lineárně interpoluje mezi předchozí a
aktuální GPS epochou.

### Vzdálenost

Přírůstek vzdálenosti se počítá lichoběžníkově:

```text
ds = (v0 + v1) / 2 * dt
```

Při překročení cílové vzdálenosti aplikace předpokládá konstantní zrychlení
mezi dvěma vzorky a dopočítá čas průchodu cílem řešením pohybové rovnice.

Tato volba je rozumná, pokud:

- jsou epochy správně seřazené;
- `dt` pochází z GPS, nikoliv z doručení přes BLE;
- chybějící vzorky jsou viditelné;
- odhad speed není zasažen krátkým outlierem.

## 1-foot rollout

Dragy vede čas prvního footu, tedy 0,3048 m, odděleně. U příslušných
vzdálenostních režimů integruje až k cílové vzdálenosti zvětšené o jeden foot
a odečte čas prvního footu.

Pro produktové porovnávání musí OpenDragy ukládat a zobrazovat obě jasně
pojmenované hodnoty:

- skutečný čas od rozjezdu bez rollout;
- čas s 1-foot rollout.

Tvrzení pro zákazníky nesmí tyto režimy míchat.

## Chybějící data a kvalita jízdy

Dragy při mezeře delší než 0,15 s dopočítá/eviduje chybějící epochy. Nalezená
validace novějších zařízení používá přibližně tato pravidla:

- průměrné `pDOP` nejvýše 2,0;
- buď alespoň 8 satelitů a průměr C/N0 nejsilnějších čtyř alespoň 40;
- nebo alespoň 10 satelitů a průměr C/N0 nejsilnějších čtyř alespoň 35;
- nejvýše 3 chybějící pakety;
- sklon v povoleném pásmu přibližně ±1 % s ohledem na směr měření.

Jde o důležitější referenční poznatek než samotná interpolace: transportní
ztráta se nemá potichu maskovat. Musí být změřena a může zneplatnit výsledek.

Číselné limity není vhodné slepě kopírovat. Například tři pakety znamenají
jinou dobu při 10, 20 a 25 Hz. OpenDragy má limit formulovat podle délky mezery,
počtu po sobě chybějících epoch a podílu ztrát.

## IMU a orientace

V BLE definici Dragy existuje motion charakteristika s krátkým UUID `FD05` a
metoda pro zapnutí notifikací. V analyzovaných aplikacích ale nebylo nalezeno:

- aktivní zapnutí této charakteristiky v měřicí cestě;
- dekódování accel/gyro vzorků;
- quaternion nebo automatické určení orientace;
- Madgwick, Mahony nebo Kalman filtr;
- použití IMU k opravě startovního času.

Callback používaný při měření obsluhuje GPS, SPP a přenos souborů. Uložené
záznamy Lite/Pro jsou následně přehrávány jako PVT/SAT/DOP.

Bez firmwaru proto lze bezpečně říct pouze:

> Android výpočet, který byl nalezen, je GPS-only. Přítomnost motion BLE
> charakteristiky nedokazuje IMU fusion.

Stejný závěr platí i pro standardní Dragy 2.30 build 201 z telefonu:
`setMotionDataNotify()` je deklarována, ale v kódu aplikace nebylo nalezeno
její volání ani spotřebitel IMU paketů. Oficiální web navíc v době rozboru
uváděl, že další funkce s integrovaným IMU algoritmem mají přijít v roce 2026.

Pro OpenDragy z toho plyne, že IMU fusion nemá blokovat opravu GPS-only
výpočtu. IMU může zůstat paralelní experiment s vlastním timestampem,
orientací, confidence a možností úplného fallbacku na GPS.

## Dopady pro OpenDragy

### Převzít jako princip

- Jedna GPS časová doména založená na `iTOW`.
- Kontrola UBX checksumu a validity fixu před fyzikou.
- Explicitní evidence duplicit, pořadí a ztracených epoch.
- Interpolace rychlostních i vzdálenostních milníků.
- Quality gate, který nekvalitní jízdu nepustí do A/B porovnání.
- Satelitní kvalita včetně C/N0, ne pouze počet satelitů.
- Explicitní rollout režim.
- Raw log umožňující deterministický offline přepočet.

### Nepřebírat bez validace

- Pevný práh startu 0,8 km/h.
- Pevný limit tří ztracených paketů bez ohledu na frekvenci.
- Hodnocení pouze průměrem; OpenDragy má ukládat také nejhorší intervaly a
  percentily.
- Předpoklad, že více desetinných míst po interpolaci znamená odpovídající
  přesnost.

### Nové bezprostřední úkoly

1. Dokončit opravy P0.1 až P0.4 a GPS-only replay core.
2. Přidat klasifikaci epoch a quality report.
3. Přidat NAV-SAT souhrn, zejména C/N0 nejsilnějších satelitů.
4. Ověřit skutečný stabilní GNSS rate konkrétního OpenDragy hardwaru.
5. Porovnat 0,5 a 0,8km/h retroaktivní start proti komerčnímu Dragy a videu.
6. Validovat bez-rollout i 1-foot rollout zvlášť.
7. Teprve paralelně zavést timestampované dávky IMU a experimentální fusion.

## Kde je hranice tohoto rozboru

Statická dekompilace není náhrada za měření na stole ani za firmware review.
Nejlepší další validační experiment je současně zaznamenat:

- raw OpenDragy PVT;
- raw nebo exportovaný výsledek Dragy;
- vysokorychlostní video společného startu;
- skutečné mezery a rate obou GPS streamů.

Tak lze oddělit algoritmický rozdíl, transportní ztrátu a fyzickou chybu GNSS,
což samotná dekompilace nedokáže.
