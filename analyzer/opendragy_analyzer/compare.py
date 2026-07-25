"""Stock vs Modified comparison helpers."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .runs import DetectedRun, RunMetrics


# Display rows for e-shop style report: (key, label, unit, higher_is_better)
COMPARE_ROWS: list[tuple[str, str, str, bool]] = [
    ("time_0_100kmh", "0–100 km/h", "s", False),
    ("time_0_100kmh_rollout", "0–100 km/h (1 ft)", "s", False),
    ("time_0_60mph", "0–60 mph", "s", False),
    ("time_60ft", "60 ft", "s", False),
    ("time_60ft_rollout", "60 ft (1 ft)", "s", False),
    ("time_18", "1/8 mile", "s", False),
    ("trap_18_kmh", "1/8 trap", "km/h", True),
    ("time_14", "1/4 mile", "s", False),
    ("time_14_rollout", "1/4 mile (1 ft)", "s", False),
    ("trap_14_kmh", "1/4 trap", "km/h", True),
    ("trap_14_rollout_kmh", "1/4 trap (1 ft)", "km/h", True),
    ("vmax_kmh", "Vmax", "km/h", True),
]


@dataclass
class CompareRow:
    key: str
    label: str
    unit: str
    stock: float | None
    modified: float | None
    delta: float | None
    improved: bool | None  # True if modified is better


@dataclass
class AbComparison:
    stock_label: str
    modified_label: str
    stock_run: DetectedRun
    modified_run: DetectedRun
    rows: list[CompareRow]

    def to_table_dicts(self) -> list[dict[str, Any]]:
        out = []
        for r in self.rows:
            out.append(
                {
                    "metric": r.label,
                    "stock": _fmt(r.stock, r.unit),
                    "modified": _fmt(r.modified, r.unit),
                    "delta": _fmt_delta(r.delta, r.unit, r.improved),
                    "improved": r.improved,
                }
            )
        return out


def _fmt(v: float | None, unit: str) -> str:
    if v is None:
        return "—"
    if unit == "s":
        return f"{v:.3f} s"
    return f"{v:.1f} {unit}"


def _fmt_delta(delta: float | None, unit: str, improved: bool | None) -> str:
    if delta is None:
        return "—"
    sign = "+" if delta > 0 else ""
    if unit == "s":
        text = f"{sign}{delta:.3f} s"
    else:
        text = f"{sign}{delta:.1f} {unit}"
    if improved is True:
        return f"▲ {text}" if unit != "s" else f"▼ {text}"
    if improved is False:
        return f"▼ {text}" if unit != "s" else f"▲ {text}"
    return text


def _get(m: RunMetrics, key: str) -> float | None:
    return getattr(m, key, None)


def compare_runs(
    stock: DetectedRun,
    modified: DetectedRun,
    *,
    stock_label: str = "Stock",
    modified_label: str = "Modified",
) -> AbComparison:
    rows: list[CompareRow] = []
    for key, label, unit, higher_better in COMPARE_ROWS:
        a = _get(stock.metrics, key)
        b = _get(modified.metrics, key)
        delta = None
        improved = None
        if a is not None and b is not None:
            delta = b - a
            if abs(delta) < 1e-9:
                improved = None
            elif higher_better:
                improved = b > a
            else:
                improved = b < a
        rows.append(
            CompareRow(
                key=key,
                label=label,
                unit=unit,
                stock=a,
                modified=b,
                delta=delta,
                improved=improved,
            )
        )
    return AbComparison(
        stock_label=stock_label,
        modified_label=modified_label,
        stock_run=stock,
        modified_run=modified,
        rows=rows,
    )
