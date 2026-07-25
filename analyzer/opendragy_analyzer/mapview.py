"""Folium map helpers — OSM or Google satellite tiles."""

from __future__ import annotations

from typing import Literal

import folium
import pandas as pd

from .runs import DetectedRun

TileKind = Literal["osm", "google_sat"]


def _tile_layer(kind: TileKind) -> folium.TileLayer:
    if kind == "google_sat":
        return folium.TileLayer(
            tiles="https://mt0.google.com/vt/lyrs=s&hl=en&x={x}&y={y}&z={z}",
            attr="Google",
            name="Google Satellite",
            overlay=False,
            control=True,
        )
    return folium.TileLayer(
        tiles="OpenStreetMap",
        name="OpenStreetMap",
        overlay=False,
        control=True,
    )


def build_runs_map(
    runs: list[tuple[DetectedRun, str, str]],
    *,
    tiles: TileKind = "osm",
    zoom_start: int = 16,
) -> folium.Map:
    """
    runs: list of (DetectedRun, display_name, color hex)
    """
    points: list[tuple[float, float]] = []
    for run, _, _ in runs:
        g = run.gps.dropna(subset=["lat", "lon"])
        for _, row in g.iterrows():
            points.append((float(row["lat"]), float(row["lon"])))

    if not points:
        m = folium.Map(location=[49.2, 16.6], zoom_start=6)
        _tile_layer(tiles).add_to(m)
        return m

    lats = [p[0] for p in points]
    lons = [p[1] for p in points]
    center = (sum(lats) / len(lats), sum(lons) / len(lons))
    m = folium.Map(location=center, zoom_start=zoom_start, tiles=None)
    _tile_layer(tiles).add_to(m)

    for run, name, color in runs:
        g = run.gps.dropna(subset=["lat", "lon"])
        if g.empty:
            continue
        coords = list(zip(g["lat"].astype(float), g["lon"].astype(float)))
        folium.PolyLine(
            coords,
            color=color,
            weight=5,
            opacity=0.9,
            tooltip=name,
        ).add_to(m)
        folium.CircleMarker(
            location=coords[0],
            radius=5,
            color=color,
            fill=True,
            tooltip=f"{name} start",
        ).add_to(m)
        folium.CircleMarker(
            location=coords[-1],
            radius=5,
            color=color,
            fill=True,
            tooltip=f"{name} end",
        ).add_to(m)

    m.fit_bounds([[min(lats), min(lons)], [max(lats), max(lons)]])
    folium.LayerControl().add_to(m)
    return m


def session_track_map(
    gps: pd.DataFrame,
    *,
    tiles: TileKind = "osm",
    color: str = "#FFBF00",
) -> folium.Map:
    g = gps.dropna(subset=["lat", "lon"])
    if g.empty:
        m = folium.Map(location=[49.2, 16.6], zoom_start=6, tiles=None)
        _tile_layer(tiles).add_to(m)
        return m
    coords = list(zip(g["lat"].astype(float), g["lon"].astype(float)))
    center = coords[len(coords) // 2]
    m = folium.Map(location=center, zoom_start=15, tiles=None)
    _tile_layer(tiles).add_to(m)
    folium.PolyLine(coords, color=color, weight=4, opacity=0.85).add_to(m)
    m.fit_bounds([coords[0], coords[-1]])
    return m
