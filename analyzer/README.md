# OpenDragy Analyzer

Desktop GUI for logger sessions: detect pulls, Stock vs Modified report, map.

Screenshot the **A/B report** tab for e-shop product pages — no image export needed.

## Run the GUI

Double-click [`run_gui.bat`](run_gui.bat), or:

```bash
cd analyzer
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
streamlit run app.py
```

Opens in the browser (local Streamlit app).

## Workflow

1. On the phone: share a session as `.odpkg`
2. Sidebar → drop `.odpkg` (or import a folder path)
3. **A/B report** → pick Stock / Modified sessions → **Show report**
4. Screenshot the report panel (+ speed chart if you want)
5. **Map** tab for OSM / Google satellite (inspection only)

## CLI (optional)

```bash
python -m opendragy_analyzer import path\to\ride.odpkg
python -m opendragy_analyzer list
python -m opendragy_analyzer runs ride_YYYYMMDD_HHMMSS
python -m opendragy_analyzer compare ride_stock ride_mod
python -m opendragy_analyzer motec path\to\ride_YYYYMMDD_HHMMSS
```

## MoTeC i2 export (`.ld`)

Exports GPS + IMU into a Pro-enabled MoTeC `.ld` (opens in **i2 Standard** or **i2 Pro** without the paid CSV import licence).

One-time setup — MotecLogGenerator + ldparser (GPL) as optional third-party:

```bash
cd analyzer
mkdir third_party
git clone --recursive https://github.com/stevendaniluk/MotecLogGenerator.git third_party/MotecLogGenerator
```

Or set `OPEN_DRAGY_MOTEC_GEN` to an existing clone (must include the `ldparser` submodule).

```bash
python -m opendragy_analyzer motec ..\exports\mx5_20260725\ride_20260725_170849
python -m opendragy_analyzer motec ride.odpkg -o ride.ld --frequency 20 --csv
```

Channels: Speed, GPS lat/lon/alt/heading/HDOP/sats, Accel X/Y/Z, G Force Lat/Long  
(`ay` = longitudinal after the typical ESP mount).

## Data

Phone keeps 4 files while recording; share as one `.odpkg`.  
PC library: `analyzer/data/library.sqlite`.
