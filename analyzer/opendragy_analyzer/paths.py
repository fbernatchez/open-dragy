from __future__ import annotations

from pathlib import Path

ANALYZER_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ANALYZER_ROOT / "data"
DEFAULT_DB = DATA_DIR / "library.sqlite"


def ensure_data_dir() -> Path:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    return DATA_DIR
