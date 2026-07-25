"""Detect acceleration runs inside continuous logger GPS and score drag metrics."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any

import numpy as np
import pandas as pd

# Match OpenDragy PhysicsEngine targets (meters / km/h).
DIST_1FT = 0.3048
DIST_60FT = 18.288
DIST_330FT = 100.584
DIST_18 = 201.168
DIST_1000FT = 304.8
DIST_14 = 402.336
DIST_12 = 804.672

LAUNCH_COMMIT_KMH = 3.0
ZERO_CROSS_KMH = 0.5
IDLE_KMH = 2.5
END_KMH = 4.0
MIN_PEAK_KMH = 25.0
MIN_RUN_DURATION_S = 2.0
MAX_RUN_DURATION_S = 90.0
END_IDLE_SAMPLES = 8


@dataclass
class RunMetrics:
    """Timed milestones for one detected pull (seconds / km/h)."""

    vmax_kmh: float | None = None
    distance_m: float | None = None
    duration_s: float | None = None

    # Absolute from launch commit (speed crosses 3 km/h), like live app elapsed.
    time_60ft: float | None = None
    time_330ft: float | None = None
    time_18: float | None = None
    time_1000ft: float | None = None
    time_14: float | None = None
    time_12: float | None = None

    trap_18_kmh: float | None = None
    trap_1000_kmh: float | None = None
    trap_14_kmh: float | None = None
    trap_12_kmh: float | None = None

    time_0_60mph: float | None = None
    time_0_100kmh: float | None = None
    time_0_100mph: float | None = None
    time_0_200kmh: float | None = None

    # NHRA-style: subtract 1 ft rollout time from absolute times.
    rollout_1ft: float | None = None
    time_60ft_rollout: float | None = None
    time_14_rollout: float | None = None
    time_0_100kmh_rollout: float | None = None
    trap_14_rollout_kmh: float | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class DetectedRun:
    session_id: str
    run_index: int
    start_ms: int
    end_ms: int
    metrics: RunMetrics
    # Slice of GPS for charts / map (elapsed relative to run start = 0 at launch).
    gps: pd.DataFrame = field(repr=False)
    label: str = ""

    @property
    def run_id(self) -> str:
        return f"{self.session_id}#r{self.run_index}"


def _interp_time(
    t0: float, t1: float, v0: float, v1: float, target: float
) -> float:
    if t1 <= t0:
        return t1
    if abs(v1 - v0) < 1e-9:
        return t1
    frac = (target - v0) / (v1 - v0)
    return t0 + (t1 - t0) * float(np.clip(frac, 0.0, 1.0))


def _interp_speed_at_distance(
    dist0: float,
    dist1: float,
    speed0: float,
    speed1: float,
    target_dist: float,
) -> float:
    if dist1 <= dist0:
        return speed1
    frac = (target_dist - dist0) / (dist1 - dist0)
    return speed0 + (speed1 - speed0) * float(np.clip(frac, 0.0, 1.0))


def score_gps_segment(gps: pd.DataFrame) -> tuple[RunMetrics, pd.DataFrame]:
    """
    Score a GPS segment that already starts near launch.
    Returns metrics + normalized dataframe (t_s from launch, distance_m).
    """
    df = gps.dropna(subset=["elapsed_ms", "speed_kmh"]).copy()
    df = df.sort_values("elapsed_ms").reset_index(drop=True)
    if len(df) < 3:
        return RunMetrics(), df

    t_ms = df["elapsed_ms"].to_numpy(dtype=float)
    speed = df["speed_kmh"].to_numpy(dtype=float)

    # Find launch commit index (first sample >= 3 km/h).
    commit_idx = None
    for i in range(1, len(speed)):
        if speed[i - 1] < LAUNCH_COMMIT_KMH <= speed[i]:
            commit_idx = i
            break
        if i == 1 and speed[0] >= LAUNCH_COMMIT_KMH:
            commit_idx = 0
            break
    if commit_idx is None:
        # Treat first rising edge after min as commit
        commit_idx = int(np.argmax(speed > LAUNCH_COMMIT_KMH))
        if speed[commit_idx] < LAUNCH_COMMIT_KMH:
            return RunMetrics(), df

    if commit_idx > 0:
        t_launch_ms = _interp_time(
            t_ms[commit_idx - 1],
            t_ms[commit_idx],
            speed[commit_idx - 1],
            speed[commit_idx],
            LAUNCH_COMMIT_KMH,
        )
    else:
        t_launch_ms = t_ms[0]

    # Zero-crossing refine: extrapolate back to 0.5 km/h if previous sample is slow.
    if commit_idx > 0 and speed[commit_idx - 1] < ZERO_CROSS_KMH:
        t_launch_ms = _interp_time(
            t_ms[commit_idx - 1],
            t_ms[commit_idx],
            speed[commit_idx - 1],
            speed[commit_idx],
            ZERO_CROSS_KMH,
        )

    # Integrate distance from launch using trapezoidal speed.
    times_s = (t_ms - t_launch_ms) / 1000.0
    dist = np.zeros(len(df))
    for i in range(1, len(df)):
        dt = max(0.0, times_s[i] - times_s[i - 1])
        v_ms = 0.5 * (speed[i] + speed[i - 1]) / 3.6
        dist[i] = dist[i - 1] + v_ms * dt

    df = df.copy()
    df["t_s"] = times_s
    df["distance_m"] = dist

    m = RunMetrics(
        vmax_kmh=float(np.nanmax(speed)),
        distance_m=float(dist[-1]),
        duration_s=float(times_s[-1]),
    )

    def hit_distance(target: float) -> tuple[float | None, float | None]:
        for i in range(1, len(dist)):
            if dist[i - 1] < target <= dist[i]:
                frac = (target - dist[i - 1]) / max(dist[i] - dist[i - 1], 1e-9)
                t = times_s[i - 1] + (times_s[i] - times_s[i - 1]) * frac
                spd = _interp_speed_at_distance(
                    dist[i - 1], dist[i], speed[i - 1], speed[i], target
                )
                return float(t), float(spd)
        return None, None

    def hit_speed(target_kmh: float) -> float | None:
        for i in range(1, len(speed)):
            if speed[i - 1] < target_kmh <= speed[i]:
                return float(
                    _interp_time(
                        times_s[i - 1],
                        times_s[i],
                        speed[i - 1],
                        speed[i],
                        target_kmh,
                    )
                )
        return None

    m.time_60ft, _ = hit_distance(DIST_60FT)
    m.time_330ft, _ = hit_distance(DIST_330FT)
    m.time_18, m.trap_18_kmh = hit_distance(DIST_18)
    m.time_1000ft, m.trap_1000_kmh = hit_distance(DIST_1000FT)
    m.time_14, m.trap_14_kmh = hit_distance(DIST_14)
    m.time_12, m.trap_12_kmh = hit_distance(DIST_12)

    m.time_0_60mph = hit_speed(96.5606)
    m.time_0_100kmh = hit_speed(100.0)
    m.time_0_100mph = hit_speed(160.934)
    m.time_0_200kmh = hit_speed(200.0)

    m.rollout_1ft, _ = hit_distance(DIST_1FT)
    if m.rollout_1ft is not None:
        r = m.rollout_1ft
        if m.time_60ft is not None:
            m.time_60ft_rollout = m.time_60ft - r
        if m.time_14 is not None:
            m.time_14_rollout = m.time_14 - r
        if m.time_0_100kmh is not None:
            m.time_0_100kmh_rollout = m.time_0_100kmh - r
        # Trap at 1/4 + 1ft (same trap speed approx as 1/4 for display)
        _, trap_r = hit_distance(DIST_14 + DIST_1FT)
        m.trap_14_rollout_kmh = trap_r if trap_r is not None else m.trap_14_kmh

    return m, df


def detect_runs(
    session_id: str,
    gps: pd.DataFrame,
    *,
    min_peak_kmh: float = MIN_PEAK_KMH,
    min_duration_s: float = MIN_RUN_DURATION_S,
) -> list[DetectedRun]:
    """Find standing-start style pulls in a continuous GPS log."""
    df = gps.dropna(subset=["elapsed_ms", "speed_kmh"]).copy()
    df = df.sort_values("elapsed_ms").reset_index(drop=True)
    if len(df) < 10:
        return []

    speed = df["speed_kmh"].to_numpy(dtype=float)
    t_ms = df["elapsed_ms"].to_numpy(dtype=int)

    runs: list[DetectedRun] = []
    i = 0
    n = len(df)
    run_index = 0

    while i < n - 2:
        # Seek idle
        while i < n and speed[i] >= IDLE_KMH:
            i += 1
        while i < n and speed[i] < LAUNCH_COMMIT_KMH:
            i += 1
        if i >= n - 2:
            break

        start_i = max(0, i - 3)
        # Expand forward until end condition
        peak = speed[i]
        idle_streak = 0
        j = i
        while j < n:
            peak = max(peak, speed[j])
            dur_s = (t_ms[j] - t_ms[start_i]) / 1000.0
            if dur_s > MAX_RUN_DURATION_S:
                break
            if peak >= min_peak_kmh and speed[j] < END_KMH:
                idle_streak += 1
                if idle_streak >= END_IDLE_SAMPLES:
                    break
            else:
                idle_streak = 0
            j += 1

        end_i = max(start_i + 2, j)
        seg = df.iloc[start_i : end_i + 1].copy()
        metrics, scored = score_gps_segment(seg)
        dur = metrics.duration_s or 0.0
        vmax = metrics.vmax_kmh or 0.0
        if dur >= min_duration_s and vmax >= min_peak_kmh:
            runs.append(
                DetectedRun(
                    session_id=session_id,
                    run_index=run_index,
                    start_ms=int(t_ms[start_i]),
                    end_ms=int(t_ms[min(end_i, n - 1)]),
                    metrics=metrics,
                    gps=scored,
                    label=f"Run {run_index + 1}",
                )
            )
            run_index += 1
        i = end_i + 1

    return runs


def pick_best_run(runs: list[DetectedRun]) -> DetectedRun | None:
    """Prefer longest 1/4-mile completion, else highest vmax."""
    if not runs:
        return None
    with_qtr = [r for r in runs if r.metrics.time_14 is not None]
    if with_qtr:
        return min(with_qtr, key=lambda r: r.metrics.time_14 or 1e9)
    return max(runs, key=lambda r: r.metrics.vmax_kmh or 0.0)
