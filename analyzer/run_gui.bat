@echo off
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
  echo Creating venv...
  py -3 -m venv .venv
  call .venv\Scripts\pip install -r requirements.txt
)
echo Starting OpenDragy Analyzer...
call .venv\Scripts\streamlit run app.py --server.headless false
