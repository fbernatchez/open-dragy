"""Pack / unpack OpenDragy `.odpkg` session archives."""

from __future__ import annotations

import json
import shutil
import tempfile
import zipfile
from pathlib import Path
from typing import Any

INNER_MANIFEST = "manifest.json"
INNER_GPX = "track.gpx"
INNER_GPS = "gps.csv"
INNER_IMU = "imu.csv"


class PackageError(ValueError):
    pass


def _read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _session_files_from_phone_layout(
    directory: Path, session_id: str, manifest: dict[str, Any]
) -> tuple[Path, Path, Path]:
    files = manifest.get("files") or {}
    gpx = directory / str(files.get("gpx", f"{session_id}.gpx"))
    gps = directory / str(files.get("gps_csv", f"{session_id}_gps.csv"))
    imu = directory / str(files.get("imu_csv", f"{session_id}_imu.csv"))
    return gpx, gps, imu


def resolve_session_dir(
    directory: Path,
) -> tuple[dict[str, Any], Path, Path, Path]:
    """
    Resolve a directory that already contains session files.
    Supports:
      - .odpkg extract layout (manifest.json + track.gpx + gps.csv + imu.csv)
      - phone layout (*.odlog.json + *.gpx + *_gps.csv + *_imu.csv)
    """
    directory = directory.resolve()
    if not directory.is_dir():
        raise PackageError(f"Not a directory: {directory}")

    odpkg_manifest = directory / INNER_MANIFEST
    if odpkg_manifest.exists():
        manifest = _read_json(odpkg_manifest)
        gpx = directory / INNER_GPX
        gps = directory / INNER_GPS
        imu = directory / INNER_IMU
    else:
        odlogs = sorted(directory.glob("*.odlog.json"))
        if len(odlogs) != 1:
            raise PackageError(
                f"Expected one .odlog.json in {directory}, found {len(odlogs)}"
            )
        manifest = _read_json(odlogs[0])
        sid = str(
            manifest.get("sessionId")
            or odlogs[0].name.removesuffix(".odlog.json")
        )
        gpx, gps, imu = _session_files_from_phone_layout(directory, sid, manifest)

    for p, label in ((gpx, "gpx"), (gps, "gps.csv"), (imu, "imu.csv")):
        if not p.exists():
            raise PackageError(f"Missing {label}: {p}")
    return manifest, gpx, gps, imu


def pack_session(source: Path, out_odpkg: Path | None = None) -> Path:
    """Create `.odpkg` from folder / stem / .odlog.json."""
    directory, cleanup = open_session_source(source)
    try:
        manifest, gpx, gps, imu = resolve_session_dir(directory)
        sid = str(manifest.get("sessionId") or "session")
        if out_odpkg is None:
            out_odpkg = source.resolve().parent / f"{sid}.odpkg"
            if source.resolve().is_dir() and source.name == sid:
                out_odpkg = source.resolve().parent / f"{sid}.odpkg"
        out_odpkg = out_odpkg.resolve()
        out_odpkg.parent.mkdir(parents=True, exist_ok=True)

        with zipfile.ZipFile(
            out_odpkg, "w", compression=zipfile.ZIP_DEFLATED
        ) as zf:
            zf.writestr(
                INNER_MANIFEST,
                json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
            )
            zf.write(gpx, INNER_GPX)
            zf.write(gps, INNER_GPS)
            zf.write(imu, INNER_IMU)
        return out_odpkg
    finally:
        if cleanup:
            shutil.rmtree(directory, ignore_errors=True)


def extract_odpkg(odpkg: Path, dest: Path | None = None) -> Path:
    """Extract `.odpkg` / `.zip` to a directory; return that dir."""
    odpkg = odpkg.resolve()
    if not odpkg.is_file():
        raise PackageError(f"Not a file: {odpkg}")

    if dest is None:
        dest = Path(tempfile.mkdtemp(prefix="odpkg_"))
    else:
        dest = dest.resolve()
        if dest.exists():
            shutil.rmtree(dest)
        dest.mkdir(parents=True)

    with zipfile.ZipFile(odpkg, "r") as zf:
        names = set(zf.namelist())
        if INNER_MANIFEST in names:
            zf.extractall(dest)
        else:
            tmp = dest / "_raw"
            tmp.mkdir()
            zf.extractall(tmp)
            files = [p for p in tmp.rglob("*") if p.is_file()]
            odlog = next(
                (p for p in files if p.name.endswith(".odlog.json")), None
            )
            gpx = next((p for p in files if p.suffix.lower() == ".gpx"), None)
            gps = next((p for p in files if p.name.endswith("_gps.csv")), None)
            imu = next((p for p in files if p.name.endswith("_imu.csv")), None)
            if not all((odlog, gpx, gps, imu)):
                raise PackageError(
                    f"Zip is not an .odpkg and missing phone session files: {odpkg}"
                )
            assert odlog and gpx and gps and imu
            manifest = _read_json(odlog)
            (dest / INNER_MANIFEST).write_text(
                json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            shutil.copy2(gpx, dest / INNER_GPX)
            shutil.copy2(gps, dest / INNER_GPS)
            shutil.copy2(imu, dest / INNER_IMU)
            shutil.rmtree(tmp)

    resolve_session_dir(dest)
    return dest


def open_session_source(path: Path) -> tuple[Path, bool]:
    """
    Return (directory with session files, needs_cleanup).
    Accepts:
      - directory with phone or odpkg layout
      - path to .odlog.json
      - path stem without suffix (exports/ride_xxx) when sibling files exist
      - .odpkg / .zip
    """
    path = path.resolve()

    if path.is_dir():
        resolve_session_dir(path)
        return path, False

    suffix = path.suffix.lower()
    if suffix in {".odpkg", ".zip"}:
        return extract_odpkg(path), True

    if path.name.endswith(".odlog.json") and path.is_file():
        return path.parent, False

    # Stem path: .../ride_20260725_074918  (file does not exist, siblings do)
    if not path.exists():
        odlog = Path(str(path) + ".odlog.json")
        if odlog.is_file():
            return odlog.parent, False
        # Also try if path is written as folder name that doesn't exist
        raise PackageError(f"Session not found: {path}")

    # Existing file that is not zip/odlog — treat parent + stem
    stem = path.name
    if stem.endswith(".odlog.json"):
        return path.parent, False
    odlog = path.parent / f"{path.name}.odlog.json"
    if odlog.is_file():
        return path.parent, False

    raise PackageError(f"Unsupported path: {path}")
