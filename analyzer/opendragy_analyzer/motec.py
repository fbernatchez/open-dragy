"""Export OpenDragy logger sessions to MoTeC i2 `.ld` files.

Uses MotecLogGenerator + ldparser (optional third-party). See analyzer/README.md.
Native `.ld` opens in i2 Standard/Pro without the paid CSV import licence.
"""

from __future__ import annotations

import json
import math
import os
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from .package import PackageError, open_session_source, resolve_session_dir


# (name, units, decimals) — Motec channel meta
_CHANNEL_SPEC: list[tuple[str, str, int]] = [
    ("Speed", "km/h", 1),
    ("GPS Speed", "km/h", 1),
    ("GPS Latitude", "deg", 7),
    ("GPS Longitude", "deg", 7),
    ("GPS Altitude", "m", 1),
    ("GPS Heading", "deg", 1),
    ("GPS HDOP", "", 2),
    ("GPS Sats", "", 0),
    ("GPS HAcc", "m", 2),
    ("Accel X", "G", 3),
    ("Accel Y", "G", 3),
    ("Accel Z", "G", 3),
    ("G Force Lat", "G", 3),  # ax — typical ESP mount
    ("G Force Long", "G", 3),  # ay — longitudinal after 90° mount
]


@dataclass(frozen=True)
class MotecExportResult:
    ld_path: Path
    csv_path: Path | None
    duration_s: float
    frequency_hz: float
    channels: int
    samples: int


class MotecExportError(RuntimeError):
    pass


def default_motec_generator_dir() -> Path | None:
    """Locate MotecLogGenerator (env, analyzer/third_party, or exports/)."""
    env = os.environ.get("OPEN_DRAGY_MOTEC_GEN", "").strip()
    if env:
        p = Path(env).expanduser().resolve()
        if (p / "motec_log.py").is_file():
            return p

    here = Path(__file__).resolve().parent.parent  # analyzer/
    repo = here.parent
    candidates = [
        here / "third_party" / "MotecLogGenerator",
        repo / "exports" / "MotecLogGenerator",
        repo / "third_party" / "MotecLogGenerator",
    ]
    for c in candidates:
        if (c / "motec_log.py").is_file():
            return c.resolve()
    return None


def _parse_started_at(manifest: dict[str, Any]) -> datetime:
    raw = str(manifest.get("startedAt") or "").strip()
    if not raw:
        return datetime.now(timezone.utc).replace(tzinfo=None)
    try:
        # 2026-07-25T15:08:49.017620Z
        if raw.endswith("Z"):
            raw = raw[:-1] + "+00:00"
        dt = datetime.fromisoformat(raw)
        if dt.tzinfo is not None:
            dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
        return dt
    except ValueError:
        return datetime.now(timezone.utc).replace(tzinfo=None)


def resolve_export_inputs(path: Path) -> tuple[dict[str, Any], Path, Path]:
    """
    Resolve (manifest, gps_csv, imu_csv) from:
      - .odlog.json / session stem (works with multiple sessions in one folder)
      - directory with a single session
    """
    path = path.resolve()

    if path.name.endswith(".odlog.json") and path.is_file():
        manifest = json.loads(path.read_text(encoding="utf-8"))
        sid = str(manifest.get("sessionId") or path.name.removesuffix(".odlog.json"))
        files = manifest.get("files") or {}
        directory = path.parent
        gps = directory / str(files.get("gps_csv", f"{sid}_gps.csv"))
        imu = directory / str(files.get("imu_csv", f"{sid}_imu.csv"))
        if not gps.is_file() or not imu.is_file():
            raise PackageError(f"Missing GPS/IMU CSV next to {path.name}")
        return manifest, gps, imu

    # Stem: .../ride_xxx (file may not exist)
    stem_odlog = Path(str(path) + ".odlog.json")
    if stem_odlog.is_file():
        return resolve_export_inputs(stem_odlog)

    if path.is_dir():
        manifest, _gpx, gps, imu = resolve_session_dir(path)
        return manifest, gps, imu

    raise PackageError(f"Unsupported MoTeC export path: {path}")


def _interp_series(
    t_out: np.ndarray, t_src: np.ndarray, y_src: np.ndarray
) -> np.ndarray:
    if len(t_src) == 0:
        return np.zeros_like(t_out)
    if len(t_src) == 1:
        return np.full_like(t_out, float(y_src[0]), dtype=np.float64)
    # np.interp needs finite values; fill NaN with neighbour / 0
    y = y_src.astype(np.float64, copy=True)
    mask = np.isfinite(y)
    if not mask.any():
        return np.zeros_like(t_out)
    if not mask.all():
        y[~mask] = np.interp(t_src[~mask], t_src[mask], y[mask])
    return np.interp(t_out, t_src, y)


def _read_logger_csv(path: Path) -> pd.DataFrame:
    """Read phone CSV; skip rare glued/truncated rows from concurrent writes."""
    try:
        df = pd.read_csv(path, on_bad_lines="skip")
    except TypeError:
        df = pd.read_csv(path, error_bad_lines=False, warn_bad_lines=False)
    return df


def build_motec_frame(
    gps: pd.DataFrame,
    imu: pd.DataFrame,
    frequency_hz: float = 20.0,
) -> tuple[pd.DataFrame, float]:
    """Resample GPS+IMU onto a fixed time grid. Returns (frame, duration_s)."""
    if gps.empty:
        raise MotecExportError("GPS CSV is empty")

    g = gps.copy()
    g["elapsed_ms"] = pd.to_numeric(g["elapsed_ms"], errors="coerce")
    if "lat" in g.columns:
        g["lat"] = pd.to_numeric(g["lat"], errors="coerce")
    if "lon" in g.columns:
        g["lon"] = pd.to_numeric(g["lon"], errors="coerce")
    need = ["elapsed_ms"]
    if "lat" in g.columns:
        need.append("lat")
    if "lon" in g.columns:
        need.append("lon")
    g = g.dropna(subset=need).sort_values("elapsed_ms")
    # Drop duplicate / non-monotonic stamps (keeps last)
    g = g.drop_duplicates(subset=["elapsed_ms"], keep="last")
    if g.empty:
        raise MotecExportError("No valid GPS timestamps")

    t0 = float(g["elapsed_ms"].iloc[0]) / 1000.0
    t1 = float(g["elapsed_ms"].iloc[-1]) / 1000.0
    if t1 <= t0:
        raise MotecExportError("GPS duration is zero")

    freq = float(frequency_hz)
    if freq <= 0:
        raise MotecExportError("frequency_hz must be > 0")

    n = max(2, int(math.floor(freq * (t1 - t0))) + 1)
    t = t0 + np.arange(n, dtype=np.float64) / freq
    # Clamp last sample inside source range
    t = np.clip(t, t0, t1)

    gt = g["elapsed_ms"].to_numpy(dtype=np.float64) / 1000.0

    def gcol(name: str) -> np.ndarray:
        if name not in g.columns:
            return np.zeros(len(gt), dtype=np.float64)
        return pd.to_numeric(g[name], errors="coerce").to_numpy(dtype=np.float64)

    speed = _interp_series(t, gt, gcol("speed_kmh"))
    lat = _interp_series(t, gt, gcol("lat"))
    lon = _interp_series(t, gt, gcol("lon"))
    alt = _interp_series(t, gt, gcol("alt_m"))
    heading = _interp_series(t, gt, gcol("heading_deg"))
    hdop = _interp_series(t, gt, gcol("hdop"))
    sats = _interp_series(t, gt, gcol("sats"))
    hacc = _interp_series(t, gt, gcol("hacc_m"))

    ax = ay = az = np.zeros_like(t)
    if not imu.empty and "elapsed_ms" in imu.columns:
        i = imu.copy()
        i["elapsed_ms"] = pd.to_numeric(i["elapsed_ms"], errors="coerce")
        i = i.dropna(subset=["elapsed_ms"]).sort_values("elapsed_ms")
        if not i.empty:
            it = i["elapsed_ms"].to_numpy(dtype=np.float64) / 1000.0

            def icol(name: str) -> np.ndarray:
                if name not in i.columns:
                    return np.zeros(len(it), dtype=np.float64)
                return pd.to_numeric(i[name], errors="coerce").to_numpy(
                    dtype=np.float64
                )

            ax = _interp_series(t, it, icol("ax_g"))
            ay = _interp_series(t, it, icol("ay_g"))
            az = _interp_series(t, it, icol("az_g"))

    # Time column for MotecLogGenerator CSV path: seconds from session start
    time_s = t - t0
    frame = pd.DataFrame(
        {
            "time": time_s,
            "Speed": speed,
            "GPS Speed": speed,
            "GPS Latitude": lat,
            "GPS Longitude": lon,
            "GPS Altitude": alt,
            "GPS Heading": heading,
            "GPS HDOP": hdop,
            "GPS Sats": sats,
            "GPS HAcc": hacc,
            "Accel X": ax,
            "Accel Y": ay,
            "Accel Z": az,
            "G Force Lat": ax,
            "G Force Long": ay,
        }
    )
    return frame, float(t1 - t0)


def write_motec_csv(frame: pd.DataFrame, path: Path) -> Path:
    path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False, float_format="%.8g")
    return path


def _import_motec_log(generator_dir: Path) -> Any:
    gen = generator_dir.resolve()
    if not (gen / "motec_log.py").is_file():
        raise MotecExportError(f"MotecLogGenerator not found at {gen}")
    ld_root = gen / "ldparser"
    if not ld_root.exists():
        raise MotecExportError(
            f"ldparser submodule missing under {gen}. "
            "Clone with --recursive or: git submodule update --init --recursive"
        )

    # MotecLogGenerator: `from ldparser.ldparser import ...` / `from motec_log import ...`
    # data_log.py imports cantools even for CSV/.ld write — stub if missing.
    if "cantools" not in sys.modules:
        import types

        sys.modules["cantools"] = types.ModuleType("cantools")

    if str(gen) not in sys.path:
        sys.path.insert(0, str(gen))
    try:
        from motec_log import MotecLog  # type: ignore
        from ldparser.ldparser import ldChan  # type: ignore
    except ImportError as e:
        raise MotecExportError(
            f"Failed to import MotecLogGenerator from {gen}: {e}"
        ) from e
    return MotecLog, ldChan


def _add_channel_array(
    motec_log: Any,
    ld_chan_cls: Any,
    name: str,
    units: str,
    values: np.ndarray,
    frequency_hz: int,
) -> None:
    """Append one channel; values must already be at fixed frequency_hz."""
    motec_log.ld_header.data_ptr += motec_log.CHANNEL_HEADER_SIZE
    for ld_channel in motec_log.ld_channels:
        ld_channel.data_ptr += motec_log.CHANNEL_HEADER_SIZE

    if motec_log.ld_channels:
        meta_ptr = motec_log.ld_channels[-1].next_meta_ptr
        prev_meta_ptr = motec_log.ld_channels[-1].meta_ptr
        data_ptr = (
            motec_log.ld_channels[-1].data_ptr
            + motec_log.ld_channels[-1]._data.nbytes
        )
    else:
        meta_ptr = motec_log.HEADER_PTR
        prev_meta_ptr = 0
        data_ptr = motec_log.ld_header.data_ptr
    next_meta_ptr = meta_ptr + motec_log.CHANNEL_HEADER_SIZE

    data = np.asarray(values, dtype=np.float32)
    freq = max(1, int(frequency_hz))
    ld_channel = ld_chan_cls(
        None,
        meta_ptr,
        prev_meta_ptr,
        next_meta_ptr,
        data_ptr,
        len(data),
        np.float32,
        freq,
        0,
        1,
        1,
        0,  # decimals: ldparser quirk
        name,
        "",
        units,
    )
    ld_channel._data = data
    motec_log.ld_channels.append(ld_channel)


def write_motec_ld(
    frame: pd.DataFrame,
    out_ld: Path,
    *,
    manifest: dict[str, Any] | None = None,
    frequency_hz: float = 20.0,
    generator_dir: Path | None = None,
    driver: str = "",
    venue_name: str = "",
    event_name: str = "OpenDragy",
    short_comment: str = "",
) -> Path:
    """Write a Pro-enabled MoTeC `.ld` from a resampled frame (with `time` col)."""
    gen = generator_dir or default_motec_generator_dir()
    if gen is None:
        raise MotecExportError(
            "MotecLogGenerator not found. Clone it to analyzer/third_party/"
            "MotecLogGenerator (with --recursive) or set OPEN_DRAGY_MOTEC_GEN."
        )

    MotecLog, ldChan = _import_motec_log(gen)

    manifest = manifest or {}
    vehicle = str(manifest.get("vehicle") or "")
    sid = str(manifest.get("sessionId") or out_ld.stem)
    notes = str(manifest.get("notes") or "")
    comment = short_comment or notes or sid
    freq_i = max(1, int(round(frequency_hz)))

    motec_log = MotecLog()
    motec_log.driver = driver
    motec_log.vehicle_id = (vehicle or sid)[:16]
    motec_log.vehicle_type = vehicle
    motec_log.vehicle_comment = notes
    motec_log.venue_name = venue_name
    motec_log.event_name = event_name
    motec_log.event_session = sid
    motec_log.long_comment = notes
    motec_log.short_comment = comment[:64]
    motec_log.datetime = _parse_started_at(manifest)
    motec_log.initialize()

    for name, units, _decimals in _CHANNEL_SPEC:
        if name not in frame.columns:
            continue
        _add_channel_array(
            motec_log,
            ldChan,
            name,
            units,
            frame[name].to_numpy(dtype=np.float64),
            freq_i,
        )

    out_ld = out_ld.resolve()
    if out_ld.suffix.lower() != ".ld":
        out_ld = out_ld.with_suffix(".ld")
    out_ld.parent.mkdir(parents=True, exist_ok=True)
    motec_log.write(str(out_ld))
    return out_ld


def export_session_to_motec(
    path: Path,
    *,
    out: Path | None = None,
    frequency_hz: float = 20.0,
    keep_csv: bool = False,
    generator_dir: Path | None = None,
    driver: str = "",
    venue_name: str = "",
    event_name: str = "OpenDragy",
) -> MotecExportResult:
    """Full pipeline: session files → resampled channels → `.ld` (+ optional CSV)."""
    path = path.resolve()
    cleanup_dir: Path | None = None

    if path.is_file() and path.suffix.lower() in {".odpkg", ".zip"}:
        directory, cleanup = open_session_source(path)
        if cleanup:
            cleanup_dir = directory
        try:
            manifest, _gpx, gps_path, imu_path = resolve_session_dir(directory)
        except Exception:
            if cleanup_dir is not None:
                import shutil

                shutil.rmtree(cleanup_dir, ignore_errors=True)
            raise
    else:
        manifest, gps_path, imu_path = resolve_export_inputs(path)

    try:
        sid = str(manifest.get("sessionId") or path.stem)
        gps = _read_logger_csv(gps_path)
        imu = (
            _read_logger_csv(imu_path)
            if imu_path.is_file()
            else pd.DataFrame()
        )
        frame, duration_s = build_motec_frame(
            gps, imu, frequency_hz=frequency_hz
        )

        if out is None:
            # Prefer next to source odlog / stem when known
            if path.name.endswith(".odlog.json"):
                out = path.parent / f"{sid}.ld"
            elif (Path(str(path) + ".odlog.json")).is_file():
                out = path.parent / f"{sid}.ld"
            else:
                out = gps_path.parent / f"{sid}.ld"
        out = out.resolve()

        csv_path: Path | None = None
        if keep_csv:
            csv_path = write_motec_csv(frame, out.with_suffix(".motec.csv"))

        ld_path = write_motec_ld(
            frame,
            out,
            manifest=manifest,
            frequency_hz=frequency_hz,
            generator_dir=generator_dir,
            driver=driver,
            venue_name=venue_name,
            event_name=event_name,
        )

        return MotecExportResult(
            ld_path=ld_path,
            csv_path=csv_path,
            duration_s=duration_s,
            frequency_hz=frequency_hz,
            channels=sum(1 for n, _, _ in _CHANNEL_SPEC if n in frame.columns),
            samples=len(frame),
        )
    finally:
        if cleanup_dir is not None:
            import shutil

            shutil.rmtree(cleanup_dir, ignore_errors=True)
