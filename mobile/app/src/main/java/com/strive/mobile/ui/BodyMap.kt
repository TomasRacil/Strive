package com.strive.mobile.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.strive.mobile.data.Muscles

/**
 * Schematic front and back body, with each zone coloured by how hard that muscle
 * works in the movement.
 *
 * This is a schematic, not anatomy: zones are deliberately chunky so the shape
 * stays readable on a phone. The taxonomy behind it is fine-grained - several
 * muscles share a zone and their load is summed - so replacing this drawing with
 * a 3D model later changes only this file.
 */
private data class Zone(
    val key: String,
    val x: Float,
    val y: Float,
    val w: Float,
    val h: Float,
    val round: Float = 3f,
    val circle: Boolean = false
)

private val frontZones = listOf(
    Zone("front_shoulder", 22f, 34f, 14f, 14f, circle = true),
    Zone("front_shoulder", 64f, 34f, 14f, 14f, circle = true),
    Zone("chest", 34f, 36f, 14f, 17f, round = 5f),
    Zone("chest", 52f, 36f, 14f, 17f, round = 5f),
    Zone("ribs", 34f, 54f, 32f, 6f, round = 3f),
    Zone("abs", 41f, 56f, 18f, 26f, round = 4f),
    Zone("obliques", 33f, 56f, 7f, 24f, round = 3f),
    Zone("obliques", 60f, 56f, 7f, 24f, round = 3f),
    Zone("biceps", 18f, 50f, 12f, 22f, round = 5f),
    Zone("biceps", 70f, 50f, 12f, 22f, round = 5f),
    Zone("forearm", 16f, 74f, 11f, 20f, round = 5f),
    Zone("forearm", 73f, 74f, 11f, 20f, round = 5f),
    Zone("quads", 36f, 92f, 13f, 36f, round = 6f),
    Zone("quads", 51f, 92f, 13f, 36f, round = 6f),
    Zone("calves", 37f, 132f, 11f, 26f, round = 5f),
    Zone("calves", 52f, 132f, 11f, 26f, round = 5f),
    Zone("shin", 38f, 160f, 10f, 16f, round = 4f),
    Zone("shin", 52f, 160f, 10f, 16f, round = 4f)
)

private val backZones = listOf(
    Zone("rear_shoulder", 22f, 34f, 14f, 14f, circle = true),
    Zone("rear_shoulder", 64f, 34f, 14f, 14f, circle = true),
    Zone("traps", 38f, 34f, 24f, 11f, round = 5f),
    Zone("upper_back", 39f, 46f, 22f, 12f, round = 4f),
    Zone("lats", 32f, 46f, 9f, 24f, round = 4f),
    Zone("lats", 59f, 46f, 9f, 24f, round = 4f),
    Zone("lower_back", 41f, 66f, 18f, 16f, round = 4f),
    Zone("triceps", 18f, 50f, 12f, 22f, round = 5f),
    Zone("triceps", 70f, 50f, 12f, 22f, round = 5f),
    Zone("forearm", 16f, 74f, 11f, 20f, round = 5f),
    Zone("forearm", 73f, 74f, 11f, 20f, round = 5f),
    Zone("glutes", 35f, 86f, 14f, 16f, round = 6f),
    Zone("glutes", 51f, 86f, 14f, 16f, round = 6f),
    Zone("hamstrings", 36f, 104f, 13f, 30f, round = 6f),
    Zone("hamstrings", 51f, 104f, 13f, 30f, round = 6f),
    Zone("calves", 37f, 136f, 11f, 24f, round = 5f),
    Zone("calves", 52f, 136f, 11f, 24f, round = 5f)
)

@Composable
fun BodyMap(
    loads: Map<String, Double>,
    peak: Double,
    modifier: Modifier = Modifier
) {
    val base = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.12f)
    val hot = MaterialTheme.colorScheme.primary
    val warm = MaterialTheme.colorScheme.tertiary
    val outline = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.25f)

    // Loads arrive keyed by muscle id; the figures are drawn by zone. Several
    // muscles share a zone (three triceps heads, four quads), so sum them.
    val zoneLoads = loads.entries
        .groupBy { (muscleId, _) -> Muscles.zone(muscleId) }
        .mapValues { (_, entries) -> entries.sumOf { it.value } }

    val zonePeak = zoneLoads.values.maxOrNull()?.takeIf { it > 0.0 } ?: peak

    Row(modifier = modifier.fillMaxWidth()) {
        BodyFigure("Front", frontZones, zoneLoads, zonePeak, base, hot, warm, outline, Modifier.weight(1f))
        BodyFigure("Back", backZones, zoneLoads, zonePeak, base, hot, warm, outline, Modifier.weight(1f))
    }
}

@Composable
private fun BodyFigure(
    label: String,
    zones: List<Zone>,
    loads: Map<String, Double>,
    peak: Double,
    base: Color,
    hot: Color,
    warm: Color,
    outline: Color,
    modifier: Modifier
) {
    Column(modifier) {
        Text(label, fontSize = 10.sp, color = outline, fontWeight = FontWeight.Bold)
        Canvas(
            Modifier
                .fillMaxWidth()
                .height(210.dp)
        ) {
            val scale = minOf(size.width / 100f, size.height / 190f)
            val offsetX = (size.width - 100f * scale) / 2f
            val offsetY = (size.height - 190f * scale) / 2f

            fun place(zone: Zone): Offset =
                Offset(offsetX + zone.x * scale, offsetY + zone.y * scale)

            // Silhouette: head, neck, torso, limbs. Drawn faintly so the coloured
            // zones sit on a recognisable body rather than floating.
            drawCircle(
                color = outline,
                radius = 12f * scale,
                center = Offset(offsetX + 50f * scale, offsetY + 16f * scale)
            )
            drawRoundRect(
                color = outline,
                topLeft = Offset(offsetX + 30f * scale, offsetY + 30f * scale),
                size = Size(40f * scale, 62f * scale),
                cornerRadius = CornerRadius(8f * scale)
            )

            zones.forEach { zone ->
                val load = loads[zone.key] ?: 0.0
                val intensity = (load / peak).coerceIn(0.0, 1.0).toFloat()

                val color = when {
                    intensity <= 0.02f -> base
                    else -> lerp(warm, hot, intensity)
                }

                val topLeft = place(zone)
                if (zone.circle) {
                    drawCircle(
                        color = color,
                        radius = (zone.w / 2f) * scale,
                        center = Offset(topLeft.x + zone.w / 2f * scale, topLeft.y + zone.h / 2f * scale)
                    )
                } else {
                    drawRoundRect(
                        color = color,
                        topLeft = topLeft,
                        size = Size(zone.w * scale, zone.h * scale),
                        cornerRadius = CornerRadius(zone.round * scale)
                    )
                }
            }
        }
    }
}

private fun lerp(start: Color, end: Color, fraction: Float): Color = Color(
    red = start.red + (end.red - start.red) * fraction,
    green = start.green + (end.green - start.green) * fraction,
    blue = start.blue + (end.blue - start.blue) * fraction,
    alpha = 1f
)
