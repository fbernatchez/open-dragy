"""SQLite library for multi-session compare."""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Any

import pandas as pd

from .package import open_session_source, resolve_session_dir
from .paths import DEFAULT_DB, ensure_data_dir


SCHEMA = """
CREATE TABLE IF NOT EXISTS sessions (
  session_id TEXT PRIMARY KEY,
  started_at TEXT,
  ended_at TEXT,
  vehicle TEXT,
  vehicle_id TEXT,
  notes TEXT,
  tags_json TEXT,
  track_points INTEGER,
  gps_rows_manifest INTEGER,
  gps_rows_actual INTEGER,
  imu_rows_actual INTEGER,
  duration_ms INTEGER,
  source_path TEXT,
  imported_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS tags (
  session_id TEXT NOT NULL,
  tag TEXT NOT NULL,
  PRIMARY KEY (session_id, tag),
  FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS gps (
  session_id TEXT NOT NULL,
  elapsed_ms INTEGER NOT NULL,
  time_utc TEXT,
  lat REAL,
  lon REAL,
  speed_kmh REAL,
  hacc_m REAL,
  fix_type INTEGER,
  heading_deg REAL,
  hdop REAL,
  sats INTEGER,
  alt_m REAL,
  PRIMARY KEY (session_id, elapsed_ms),
  FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS imu (
  session_id TEXT NOT NULL,
  elapsed_ms INTEGER NOT NULL,
  ax_g REAL,
  ay_g REAL,
  az_g REAL,
  PRIMARY KEY (session_id, elapsed_ms),
  FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_gps_session_elapsed ON gps(session_id, elapsed_ms);
CREATE INDEX IF NOT EXISTS idx_imu_session_elapsed ON imu(session_id, elapsed_ms);
"""


def connect(db_path: Path | None = None) -> sqlite3.Connection:
    ensure_data_dir()
    path = db_path or DEFAULT_DB
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.executescript(SCHEMA)
    return conn


def _to_float(v: Any) -> float | None:
    if v is None:
        return None
    try:
        if pd.isna(v):
            return None
    except (TypeError, ValueError):
        pass
    s = str(v).strip()
    if s == "" or s.lower() == "nan":
        return None
    try:
        return float(s)
    except ValueError:
        return None


def _to_int(v: Any) -> int | None:
    f = _to_float(v)
    return int(f) if f is not None else None


def import_session(path: Path, db_path: Path | None = None) -> str:
    """Import folder / .odpkg / .zip into the library. Returns session_id."""
    src, cleanup = open_session_source(path)
    try:
        manifest, gpx, gps_csv, imu_csv = resolve_session_dir(src)
        sid = str(manifest.get("sessionId") or path.stem)
        tags = manifest.get("tags") or []
        if not isinstance(tags, list):
            tags = []

        gps_df = pd.read_csv(gps_csv)
        imu_df = pd.read_csv(imu_csv)
        if "elapsed_ms" not in gps_df.columns:
            raise ValueError("gps.csv missing elapsed_ms")
        if "elapsed_ms" not in imu_df.columns:
            raise ValueError("imu.csv missing elapsed_ms")

        gps_df = gps_df.dropna(subset=["elapsed_ms"])
        imu_df = imu_df.dropna(subset=["elapsed_ms"])
        gps_df["elapsed_ms"] = gps_df["elapsed_ms"].astype(int)
        imu_df["elapsed_ms"] = imu_df["elapsed_ms"].astype(int)

        # Drop duplicate elapsed_ms (keep last)
        gps_df = gps_df.drop_duplicates(subset=["elapsed_ms"], keep="last")
        imu_df = imu_df.drop_duplicates(subset=["elapsed_ms"], keep="last")

        duration = None
        if len(gps_df):
            duration = int(gps_df["elapsed_ms"].max() - gps_df["elapsed_ms"].min())

        conn = connect(db_path)
        try:
            conn.execute("DELETE FROM sessions WHERE session_id = ?", (sid,))
            conn.execute(
                """
                INSERT INTO sessions (
                  session_id, started_at, ended_at, vehicle, vehicle_id, notes,
                  tags_json, track_points, gps_rows_manifest, gps_rows_actual,
                  imu_rows_actual, duration_ms, source_path
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    sid,
                    manifest.get("startedAt"),
                    manifest.get("endedAt"),
                    manifest.get("vehicle"),
                    manifest.get("vehicleId"),
                    manifest.get("notes"),
                    json.dumps(tags, ensure_ascii=False),
                    manifest.get("trackPoints"),
                    manifest.get("gpsRows"),
                    int(len(gps_df)),
                    int(len(imu_df)),
                    duration,
                    str(path.resolve()),
                ),
            )
            for tag in tags:
                t = str(tag).strip()
                if t:
                    conn.execute(
                        "INSERT OR IGNORE INTO tags(session_id, tag) VALUES (?, ?)",
                        (sid, t),
                    )

            gps_rows = []
            for _, r in gps_df.iterrows():
                gps_rows.append(
                    (
                        sid,
                        int(r["elapsed_ms"]),
                        None if pd.isna(r.get("time_utc")) else str(r.get("time_utc")),
                        _to_float(r.get("lat")),
                        _to_float(r.get("lon")),
                        _to_float(r.get("speed_kmh")),
                        _to_float(r.get("hacc_m")),
                        _to_int(r.get("fix_type")),
                        _to_float(r.get("heading_deg")),
                        _to_float(r.get("hdop")),
                        _to_int(r.get("sats")),
                        _to_float(r.get("alt_m")),
                    )
                )
            conn.executemany(
                """
                INSERT INTO gps (
                  session_id, elapsed_ms, time_utc, lat, lon, speed_kmh,
                  hacc_m, fix_type, heading_deg, hdop, sats, alt_m
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                gps_rows,
            )

            imu_rows = []
            for _, r in imu_df.iterrows():
                imu_rows.append(
                    (
                        sid,
                        int(r["elapsed_ms"]),
                        _to_float(r.get("ax_g")),
                        _to_float(r.get("ay_g")),
                        _to_float(r.get("az_g")),
                    )
                )
            conn.executemany(
                """
                INSERT INTO imu (session_id, elapsed_ms, ax_g, ay_g, az_g)
                VALUES (?, ?, ?, ?, ?)
                """,
                imu_rows,
            )
            conn.commit()
        finally:
            conn.close()

        # gpx kept on disk only for now (map later); reference via source_path
        _ = gpx
        return sid
    finally:
        if cleanup:
            shutil_rmtree_quiet(src)


def shutil_rmtree_quiet(path: Path) -> None:
    import shutil

    try:
        shutil.rmtree(path)
    except OSError:
        pass


def list_sessions(db_path: Path | None = None) -> pd.DataFrame:
    conn = connect(db_path)
    try:
        return pd.read_sql_query(
            """
            SELECT session_id, started_at, ended_at, vehicle, notes, tags_json,
                   gps_rows_actual, imu_rows_actual, duration_ms, imported_at
            FROM sessions
            ORDER BY started_at DESC
            """,
            conn,
        )
    finally:
        conn.close()


def load_gps(session_id: str, db_path: Path | None = None) -> pd.DataFrame:
    conn = connect(db_path)
    try:
        return pd.read_sql_query(
            """
            SELECT elapsed_ms, time_utc, lat, lon, speed_kmh, hdop, sats, alt_m
            FROM gps WHERE session_id = ? ORDER BY elapsed_ms
            """,
            conn,
            params=(session_id,),
        )
    finally:
        conn.close()


def load_imu(session_id: str, db_path: Path | None = None) -> pd.DataFrame:
    conn = connect(db_path)
    try:
        return pd.read_sql_query(
            """
            SELECT elapsed_ms, ax_g, ay_g, az_g
            FROM imu WHERE session_id = ? ORDER BY elapsed_ms
            """,
            conn,
            params=(session_id,),
        )
    finally:
        conn.close()
