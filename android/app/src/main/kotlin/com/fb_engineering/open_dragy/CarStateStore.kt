package com.fb_engineering.open_dragy

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class DragTargetOption(
    val name: String,
    val label: String,
)

data class CarHistoryEntry(
    val id: String,
    val title: String,
    val subtitle: String,
    val lines: List<String>,
)

data class CarVehicleOption(
    val id: String,
    val label: String,
)

/** Shared state for MediaSession metadata + Android Auto templates. */
object CarStateStore {
    @Volatile var enabled: Boolean = true
    @Volatile var armed: Boolean = false
    @Volatile var running: Boolean = false
    @Volatile var speedKmh: Double = 0.0
    @Volatile var targetLabel: String = "—"
    @Volatile var dragTargetName: String = "quarterMile"
    @Volatile var lastResult: String? = null
    @Volatile var dragTargets: List<DragTargetOption> = defaultDragTargets()
    @Volatile var vehicleId: String = ""
    @Volatile var vehicleLabel: String = "—"
    @Volatile var vehicles: List<CarVehicleOption> = emptyList()

    /** Increments when a run finishes — AA main screen pushes Finish UI. */
    @Volatile var finishToken: Int = 0
    @Volatile var finishHeadline: String = ""
    @Volatile var finishLines: List<String> = emptyList()
    @Volatile var history: List<CarHistoryEntry> = emptyList()

    fun prefs(context: Context) =
        context.getSharedPreferences("opendragy_car", Context.MODE_PRIVATE)

    fun persist(context: Context) {
        val targetsArr = JSONArray()
        for (t in dragTargets) {
            targetsArr.put(
                JSONObject().put("name", t.name).put("label", t.label),
            )
        }
        val vehiclesArr = JSONArray()
        for (v in vehicles) {
            vehiclesArr.put(
                JSONObject().put("id", v.id).put("label", v.label),
            )
        }
        val histArr = JSONArray()
        for (h in history) {
            val lines = JSONArray()
            h.lines.forEach { lines.put(it) }
            histArr.put(
                JSONObject()
                    .put("id", h.id)
                    .put("title", h.title)
                    .put("subtitle", h.subtitle)
                    .put("lines", lines),
            )
        }
        val finishArr = JSONArray()
        finishLines.forEach { finishArr.put(it) }

        prefs(context).edit()
            .putBoolean("enabled", enabled)
            .putBoolean("armed", armed)
            .putBoolean("running", running)
            .putFloat("speedKmh", speedKmh.toFloat())
            .putString("targetLabel", targetLabel)
            .putString("dragTargetName", dragTargetName)
            .putString("lastResult", lastResult)
            .putString("dragTargetsJson", targetsArr.toString())
            .putString("vehicleId", vehicleId)
            .putString("vehicleLabel", vehicleLabel)
            .putString("vehiclesJson", vehiclesArr.toString())
            .putInt("finishToken", finishToken)
            .putString("finishHeadline", finishHeadline)
            .putString("finishLinesJson", finishArr.toString())
            .putString("historyJson", histArr.toString())
            .apply()
    }

    fun load(context: Context) {
        val p = prefs(context)
        enabled = p.getBoolean("enabled", true)
        armed = p.getBoolean("armed", false)
        running = p.getBoolean("running", false)
        speedKmh = p.getFloat("speedKmh", 0f).toDouble()
        targetLabel = p.getString("targetLabel", "—") ?: "—"
        dragTargetName = p.getString("dragTargetName", "quarterMile") ?: "quarterMile"
        lastResult = p.getString("lastResult", null)
        dragTargets = parseTargets(p.getString("dragTargetsJson", null)) ?: defaultDragTargets()
        vehicleId = p.getString("vehicleId", "") ?: ""
        vehicleLabel = p.getString("vehicleLabel", "—") ?: "—"
        vehicles = parseVehicles(p.getString("vehiclesJson", null))
        finishToken = p.getInt("finishToken", 0)
        finishHeadline = p.getString("finishHeadline", "") ?: ""
        finishLines = parseStringList(p.getString("finishLinesJson", null))
        history = parseHistory(p.getString("historyJson", null))
    }

    fun statusLine(): String = when {
        running -> "RUNNING"
        armed -> "ARMED"
        else -> "IDLE"
    }

    fun titleLine(): String = "OpenDragy · ${statusLine()}"

    fun subtitleLine(): String {
        val speed = String.format("%.0f km/h", speedKmh)
        val last = lastResult
        return if (last.isNullOrBlank()) {
            "$speed · $targetLabel"
        } else {
            "$speed · $targetLabel · $last"
        }
    }

    fun nextDragTargetName(): String? {
        if (dragTargets.isEmpty()) return null
        val idx = dragTargets.indexOfFirst { it.name == dragTargetName }
        val next = if (idx < 0) 0 else (idx + 1) % dragTargets.size
        return dragTargets[next].name
    }

    private fun parseTargets(json: String?): List<DragTargetOption>? {
        if (json.isNullOrBlank()) return null
        return try {
            val arr = JSONArray(json)
            buildList {
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    add(DragTargetOption(o.getString("name"), o.getString("label")))
                }
            }.ifEmpty { null }
        } catch (_: Exception) {
            null
        }
    }

    private fun parseVehicles(json: String?): List<CarVehicleOption> {
        if (json.isNullOrBlank()) return emptyList()
        return try {
            val arr = JSONArray(json)
            buildList {
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    add(CarVehicleOption(o.getString("id"), o.getString("label")))
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun parseStringList(json: String?): List<String> {
        if (json.isNullOrBlank()) return emptyList()
        return try {
            val arr = JSONArray(json)
            buildList {
                for (i in 0 until arr.length()) add(arr.getString(i))
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun parseHistory(json: String?): List<CarHistoryEntry> {
        if (json.isNullOrBlank()) return emptyList()
        return try {
            val arr = JSONArray(json)
            buildList {
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    val linesArr = o.optJSONArray("lines") ?: JSONArray()
                    val lines = buildList {
                        for (j in 0 until linesArr.length()) add(linesArr.getString(j))
                    }
                    add(
                        CarHistoryEntry(
                            id = o.getString("id"),
                            title = o.getString("title"),
                            subtitle = o.optString("subtitle", ""),
                            lines = lines,
                        ),
                    )
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun defaultDragTargets(): List<DragTargetOption> = listOf(
        DragTargetOption("sixtyFeet", "60ft"),
        DragTargetOption("threeHundredThirtyFeet", "330ft"),
        DragTargetOption("eighthMile", "1/8 mile"),
        DragTargetOption("thousandFeet", "1000ft"),
        DragTargetOption("quarterMile", "1/4 mile"),
        DragTargetOption("halfMile", "1/2 mile"),
    )
}
