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
```

## Data

Phone keeps 4 files while recording; share as one `.odpkg`.  
PC library: `analyzer/data/library.sqlite`.
