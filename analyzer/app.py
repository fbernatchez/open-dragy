"""OpenDragy Analyzer — desktop GUI (Streamlit)."""

from __future__ import annotations

import json
import tempfile
from pathlib import Path

import plotly.graph_objects as go
import streamlit as st
from streamlit_folium import st_folium

from opendragy_analyzer.compare import compare_runs
from opendragy_analyzer.library import import_session, list_sessions, load_gps
from opendragy_analyzer.mapview import build_runs_map, session_track_map
from opendragy_analyzer.paths import DEFAULT_DB
from opendragy_analyzer.runs import detect_runs, pick_best_run

st.set_page_config(
    page_title="OpenDragy Analyzer",
    page_icon="🏁",
    layout="wide",
    initial_sidebar_state="expanded",
)

st.markdown(
    """
    <style>
    .report-wrap {
        background: #111;
        border: 1px solid #333;
        border-radius: 16px;
        padding: 1.5rem 1.75rem 1.25rem;
        margin-top: 0.5rem;
    }
    .report-title {
        text-align: center;
        font-size: 1.6rem;
        font-weight: 700;
        color: #fff;
        margin: 0 0 0.25rem 0;
    }
    .report-sub {
        text-align: center;
        color: #888;
        font-size: 0.95rem;
        margin-bottom: 1.25rem;
    }
    .col-head {
        text-align: center;
        font-weight: 700;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        font-size: 0.85rem;
        margin-bottom: 0.75rem;
    }
    .col-head.stock { color: #8FA3B5; }
    .col-head.mod { color: #E07A3D; }
    .metric-row {
        display: flex;
        justify-content: space-between;
        align-items: baseline;
        padding: 0.45rem 0;
        border-bottom: 1px solid #222;
        font-variant-numeric: tabular-nums;
    }
    .metric-label { color: #aaa; flex: 1; text-align: center; font-size: 0.92rem; }
    .metric-val { width: 30%; text-align: center; font-size: 1.15rem; font-weight: 600; }
    .metric-val.stock { color: #8FA3B5; }
    .metric-val.mod { color: #E07A3D; }
    .delta-good { color: #3DDC84; font-size: 0.85rem; font-weight: 600; }
    .delta-bad { color: #FF6B6B; font-size: 0.85rem; font-weight: 600; }
    .hint { color: #666; font-size: 0.8rem; text-align: center; margin-top: 1rem; }
    </style>
    """,
    unsafe_allow_html=True,
)

st.sidebar.title("OpenDragy Analyzer")
st.sidebar.caption("Import sessions · compare pulls · screenshot the report")

db_path = Path(st.sidebar.text_input("Library DB", value=str(DEFAULT_DB)))

st.sidebar.subheader("Import")
uploads = st.sidebar.file_uploader(
    ".odpkg / .zip",
    type=["odpkg", "zip"],
    accept_multiple_files=True,
)
if uploads:
    for up in uploads:
        with tempfile.NamedTemporaryFile(
            delete=False, suffix=Path(up.name).suffix
        ) as tmp:
            tmp.write(up.getbuffer())
            tmp_path = Path(tmp.name)
        try:
            sid = import_session(tmp_path, db_path=db_path)
            st.sidebar.success(f"Imported {sid}")
        except Exception as e:  # noqa: BLE001
            st.sidebar.error(f"{up.name}: {e}")
        finally:
            tmp_path.unlink(missing_ok=True)

folder = st.sidebar.text_input("Or folder / .odpkg path", value="")
if st.sidebar.button("Import path") and folder.strip():
    try:
        sid = import_session(Path(folder.strip()), db_path=db_path)
        st.sidebar.success(f"Imported {sid}")
    except Exception as e:  # noqa: BLE001
        st.sidebar.error(str(e))

min_peak = st.sidebar.slider("Min peak speed (km/h)", 10.0, 80.0, 25.0, 1.0)

sessions = list_sessions(db_path=db_path)
if sessions.empty:
    st.title("OpenDragy Analyzer")
    st.info("Import a logger session from the sidebar (.odpkg from the phone).")
    st.stop()

labels: list[str] = []
id_by_label: dict[str, str] = {}
for _, row in sessions.iterrows():
    try:
        tags = json.loads(row["tags_json"] or "[]")
    except json.JSONDecodeError:
        tags = []
    tag_s = ", ".join(tags) if tags else "no tags"
    label = f"{row['session_id']} · {row['vehicle'] or '?'} · {tag_s}"
    labels.append(label)
    id_by_label[label] = row["session_id"]


def _fmt(v: float | None, unit: str) -> str:
    if v is None:
        return "—"
    if unit == "s":
        return f"{v:.3f} s"
    return f"{v:.1f} {unit}"


def _delta_html(delta: float | None, unit: str, improved: bool | None) -> str:
    if delta is None or improved is None:
        return ""
    if unit == "s":
        text = f"{delta:+.3f} s"
    else:
        text = f"{delta:+.1f}"
    cls = "delta-good" if improved else "delta-bad"
    return f'<div class="{cls}">{text}</div>'


tab_report, tab_sessions, tab_map = st.tabs(["A/B report", "Sessions", "Map"])

with tab_report:
    c1, c2 = st.columns(2)
    with c1:
        stock_label_ui = st.text_input("Left label", value="Stock")
        stock_session = st.selectbox("Stock session", labels, key="stock_sess")
    with c2:
        mod_label_ui = st.text_input("Right label", value="Modified intake")
        mod_session = st.selectbox(
            "Modified session",
            labels,
            index=min(1, len(labels) - 1),
            key="mod_sess",
        )

    report_title = st.text_input(
        "Title",
        value=f"{stock_label_ui} vs {mod_label_ui}",
    )
    report_sub = st.text_input(
        "Subtitle",
        value="",
        placeholder="Honda X-ADV · same driver · same road",
    )

    if st.button("Show report", type="primary"):
        stock_sid = id_by_label[stock_session]
        mod_sid = id_by_label[mod_session]
        stock_best = pick_best_run(
            detect_runs(
                stock_sid,
                load_gps(stock_sid, db_path=db_path),
                min_peak_kmh=min_peak,
            )
        )
        mod_best = pick_best_run(
            detect_runs(
                mod_sid,
                load_gps(mod_sid, db_path=db_path),
                min_peak_kmh=min_peak,
            )
        )
        if stock_best is None or mod_best is None:
            st.error(
                "No valid pull detected. Lower min peak speed in the sidebar, "
                "or pick sessions with a real launch."
            )
            st.session_state.pop("ab", None)
        else:
            st.session_state["ab"] = compare_runs(
                stock_best,
                mod_best,
                stock_label=stock_label_ui,
                modified_label=mod_label_ui,
            )
            st.session_state["ab_title"] = report_title
            st.session_state["ab_sub"] = report_sub

    ab = st.session_state.get("ab")
    if ab is not None:
        title = st.session_state.get("ab_title") or (
            f"{ab.stock_label} vs {ab.modified_label}"
        )
        sub = st.session_state.get("ab_sub") or ""

        # Screenshot-friendly report block
        rows_html = []
        for r in ab.rows:
            if r.stock is None and r.modified is None:
                continue
            rows_html.append(
                f'<div class="metric-row">'
                f'<div class="metric-val stock">{_fmt(r.stock, r.unit)}</div>'
                f'<div class="metric-label">{r.label}'
                f"{_delta_html(r.delta, r.unit, r.improved)}</div>"
                f'<div class="metric-val mod">{_fmt(r.modified, r.unit)}</div>'
                f"</div>"
            )

        st.markdown(
            f"""
            <div class="report-wrap" id="ab-report">
              <div class="report-title">{title}</div>
              <div class="report-sub">{sub or "&nbsp;"}</div>
              <div style="display:flex;justify-content:space-between;padding:0 4%;">
                <div class="col-head stock" style="width:30%;">{ab.stock_label}</div>
                <div style="width:40%;"></div>
                <div class="col-head mod" style="width:30%;">{ab.modified_label}</div>
              </div>
              {''.join(rows_html)}
              <div class="hint">OpenDragy · screenshot this panel for the product page</div>
            </div>
            """,
            unsafe_allow_html=True,
        )

        fig = go.Figure()
        for run, name, color in (
            (ab.stock_run, ab.stock_label, "#8FA3B5"),
            (ab.modified_run, ab.modified_label, "#E07A3D"),
        ):
            g = run.gps.dropna(subset=["t_s", "speed_kmh"])
            if g.empty:
                continue
            fig.add_trace(
                go.Scatter(
                    x=g["t_s"],
                    y=g["speed_kmh"],
                    mode="lines",
                    name=name,
                    line=dict(color=color, width=3),
                )
            )
        fig.update_layout(
            title="Speed overlay",
            xaxis_title="Time (s)",
            yaxis_title="Speed (km/h)",
            height=420,
            template="plotly_dark",
            paper_bgcolor="#111",
            plot_bgcolor="#151515",
            font=dict(color="#ddd"),
            margin=dict(l=50, r=20, t=50, b=40),
            legend=dict(orientation="h", yanchor="bottom", y=1.02),
        )
        st.plotly_chart(fig, width="stretch")

with tab_sessions:
    picked = st.multiselect(
        "Sessions",
        options=labels,
        default=labels[: min(2, len(labels))],
    )
    fig = go.Figure()
    for label in picked:
        sid = id_by_label[label]
        gps = load_gps(sid, db_path=db_path)
        if gps.empty:
            continue
        t0 = float(gps["elapsed_ms"].iloc[0])
        fig.add_trace(
            go.Scatter(
                x=(gps["elapsed_ms"] - t0) / 1000.0,
                y=gps["speed_kmh"],
                mode="lines",
                name=sid,
            )
        )
        runs = detect_runs(sid, gps, min_peak_kmh=min_peak)
        st.write(f"**{sid}** — {len(runs)} run(s)")
        if runs:
            st.dataframe(
                [
                    {
                        "run": r.label,
                        "vmax": r.metrics.vmax_kmh,
                        "0-100": r.metrics.time_0_100kmh,
                        "1/4": r.metrics.time_14,
                        "trap": r.metrics.trap_14_kmh,
                    }
                    for r in runs
                ],
                width="stretch",
            )
    fig.update_layout(
        title="Full session speed",
        xaxis_title="Elapsed (s)",
        yaxis_title="km/h",
        height=400,
        template="plotly_dark",
    )
    st.plotly_chart(fig, width="stretch")

with tab_map:
    map_tiles = st.radio(
        "Tiles",
        options=["osm", "google_sat"],
        format_func=lambda x: (
            "OpenStreetMap" if x == "osm" else "Google Satellite"
        ),
        horizontal=True,
    )
    map_mode = st.radio(
        "Show",
        options=["A/B runs", "Full session"],
        horizontal=True,
    )
    if map_mode == "A/B runs":
        ab = st.session_state.get("ab")
        if ab is None:
            st.info("Open the A/B report tab and click Show report first.")
        else:
            st_folium(
                build_runs_map(
                    [
                        (ab.stock_run, ab.stock_label, "#8FA3B5"),
                        (ab.modified_run, ab.modified_label, "#E07A3D"),
                    ],
                    tiles=map_tiles,  # type: ignore[arg-type]
                ),
                width=None,
                height=560,
            )
    else:
        sess = st.selectbox("Session", labels, key="map_sess")
        st_folium(
            session_track_map(
                load_gps(id_by_label[sess], db_path=db_path),
                tiles=map_tiles,  # type: ignore[arg-type]
            ),
            width=None,
            height=560,
        )
