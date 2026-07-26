from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .compare import compare_runs
from .library import import_session, list_sessions, load_gps
from .motec import MotecExportError, export_session_to_motec
from .package import PackageError, pack_session
from .paths import DEFAULT_DB
from .runs import detect_runs, pick_best_run


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="opendragy_analyzer",
        description="Import OpenDragy logger sessions (GUI: run_gui.bat / streamlit)",
    )
    parser.add_argument(
        "--db",
        type=Path,
        default=DEFAULT_DB,
        help=f"SQLite library path (default: {DEFAULT_DB})",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_import = sub.add_parser("import", help="Import session folder / .odpkg / stem")
    p_import.add_argument("paths", nargs="+", type=Path)

    sub.add_parser("list", help="List sessions in the library")

    p_pack = sub.add_parser("pack", help="Pack phone files into .odpkg")
    p_pack.add_argument("path", type=Path)
    p_pack.add_argument("-o", "--out", type=Path, default=None)

    p_runs = sub.add_parser("runs", help="Detect pulls in a session")
    p_runs.add_argument("session_id")
    p_runs.add_argument("--min-peak", type=float, default=25.0)

    p_ab = sub.add_parser("compare", help="Print Stock vs Modified table")
    p_ab.add_argument("stock_session")
    p_ab.add_argument("modified_session")
    p_ab.add_argument("--stock-label", default="Stock")
    p_ab.add_argument("--modified-label", default="Modified intake")
    p_ab.add_argument("--min-peak", type=float, default=25.0)

    p_motec = sub.add_parser(
        "motec",
        help="Export session to MoTeC i2 .ld (needs MotecLogGenerator)",
    )
    p_motec.add_argument(
        "path",
        type=Path,
        help="Session stem, .odlog.json, folder, or .odpkg",
    )
    p_motec.add_argument(
        "-o",
        "--out",
        type=Path,
        default=None,
        help="Output .ld path (default: next to session)",
    )
    p_motec.add_argument(
        "--frequency",
        type=float,
        default=20.0,
        help="Sample rate Hz for all channels (default: 20)",
    )
    p_motec.add_argument(
        "--csv",
        action="store_true",
        help="Also write resampled .motec.csv (i2 CSV import needs a licence)",
    )
    p_motec.add_argument("--driver", default="", help="MoTeC driver metadata")
    p_motec.add_argument("--venue", default="", help="MoTeC venue metadata")
    p_motec.add_argument(
        "--event",
        default="OpenDragy",
        help="MoTeC event name (default: OpenDragy)",
    )
    p_motec.add_argument(
        "--generator",
        type=Path,
        default=None,
        help="Path to MotecLogGenerator (or set OPEN_DRAGY_MOTEC_GEN)",
    )

    args = parser.parse_args(argv)

    try:
        if args.cmd == "import":
            for p in args.paths:
                sid = import_session(p, db_path=args.db)
                print(f"imported {sid}")
            return 0
        if args.cmd == "list":
            df = list_sessions(db_path=args.db)
            if df.empty:
                print("(empty library)")
                return 0
            for _, row in df.iterrows():
                tags = row["tags_json"] or "[]"
                try:
                    tags_list = json.loads(tags)
                except json.JSONDecodeError:
                    tags_list = []
                tag_s = ",".join(tags_list) if tags_list else "-"
                dur = row["duration_ms"]
                dur_s = f"{dur / 1000:.1f}s" if dur is not None else "?"
                print(
                    f"{row['session_id']}  gps={row['gps_rows_actual']}  "
                    f"imu={row['imu_rows_actual']}  {dur_s}  "
                    f"[{tag_s}]  {row['vehicle'] or '-'}"
                )
            return 0
        if args.cmd == "pack":
            print(pack_session(args.path, out_odpkg=args.out))
            return 0
        if args.cmd == "runs":
            gps = load_gps(args.session_id, db_path=args.db)
            if gps.empty:
                print("error: session not found or empty GPS", file=sys.stderr)
                return 1
            runs = detect_runs(
                args.session_id, gps, min_peak_kmh=args.min_peak
            )
            if not runs:
                print("(no runs detected)")
                return 0
            for r in runs:
                m = r.metrics
                print(
                    f"{r.run_id}  vmax={m.vmax_kmh:.1f}  "
                    f"0-100={m.time_0_100kmh}  1/4={m.time_14}  "
                    f"trap={m.trap_14_kmh}"
                )
            return 0
        if args.cmd == "compare":
            stock = pick_best_run(
                detect_runs(
                    args.stock_session,
                    load_gps(args.stock_session, db_path=args.db),
                    min_peak_kmh=args.min_peak,
                )
            )
            modified = pick_best_run(
                detect_runs(
                    args.modified_session,
                    load_gps(args.modified_session, db_path=args.db),
                    min_peak_kmh=args.min_peak,
                )
            )
            if stock is None or modified is None:
                print(
                    "error: need a detectable pull in both sessions "
                    "(try --min-peak)",
                    file=sys.stderr,
                )
                return 1
            cmp = compare_runs(
                stock,
                modified,
                stock_label=args.stock_label,
                modified_label=args.modified_label,
            )
            print(f"{cmp.stock_label:22}  {cmp.modified_label}")
            for row in cmp.to_table_dicts():
                print(
                    f"{row['metric']:22}  {row['stock']:>12}  "
                    f"{row['modified']:>12}  {row['delta']}"
                )
            return 0
        if args.cmd == "motec":
            result = export_session_to_motec(
                args.path,
                out=args.out,
                frequency_hz=args.frequency,
                keep_csv=args.csv,
                generator_dir=args.generator,
                driver=args.driver,
                venue_name=args.venue,
                event_name=args.event,
            )
            print(
                f"wrote {result.ld_path}  "
                f"({result.duration_s / 60:.1f} min, "
                f"{result.samples} samples @ {result.frequency_hz:g} Hz, "
                f"{result.channels} channels)"
            )
            if result.csv_path:
                print(f"wrote {result.csv_path}")
            return 0
    except (PackageError, MotecExportError, OSError, ValueError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
