package com.strive.mobile.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

@Composable
fun ProgressView(state: AppState) {
    val lang = state.settings.lang
    val unit = state.settings.unit
    fun t(key: String) = Strings.t(lang, key)

    var selectedId by remember { mutableStateOf(state.exercises.firstOrNull()?.id) }

    // One short reveal per selection change. The chart draws itself left to right
    // rather than snapping in, which makes a new trend readable at a glance.
    var revealed by remember { mutableStateOf(false) }
    LaunchedEffect(selectedId) {
        revealed = false
        delay(30)
        revealed = true
    }
    val reveal by animateFloatAsState(
        targetValue = if (revealed) 1f else 0f,
        animationSpec = tween(durationMillis = 650),
        label = "chartReveal"
    )

    val exercise = state.exercises.firstOrNull { it.id == selectedId }
    val series = exercise?.let { Stats.bestPerSession(state.sessions, it.id) } ?: emptyList()
    val best = exercise?.let { Stats.bestEver(state.sessions, it.id) } ?: 0.0
    val weekly = Stats.weeklyVolume(state.sessions, 8, state.exercises, state.settings.bodyKg)

    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            state.exercises.forEach { ex ->
                FilterChip(
                    selected = ex.id == selectedId,
                    onClick = { selectedId = ex.id },
                    label = { Text(ex.name) }
                )
            }
        }

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp)) {
                Text(
                    t("prog.e1rm"),
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    Format.weight(best, unit),
                    fontSize = 30.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = MaterialTheme.colorScheme.primary
                )

                Spacer(Modifier.height(12.dp))

                if (series.size < 2) {
                    Text(
                        t("prog.noData"),
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    LineChart(
                        values = series,
                        reveal = reveal,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(140.dp)
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "${series.size} ${t("prog.sessions")}",
                        fontSize = 11.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp)) {
                Text(
                    t("prog.weekly"),
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    Format.volume(
                        Stats.totalVolume(state.sessions, state.exercises, state.settings.bodyKg),
                        unit
                    ),
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold
                )

                Spacer(Modifier.height(12.dp))

                BarChart(
                    values = weekly,
                    reveal = reveal,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(110.dp)
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    t("prog.last8"),
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun LineChart(values: List<Double>, reveal: Float, modifier: Modifier = Modifier) {
    val lineColor = MaterialTheme.colorScheme.primary
    val axisColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.25f)

    Canvas(modifier) {
        if (values.size < 2) return@Canvas

        val minValue = values.min()
        val maxValue = values.max()
        val range = (maxValue - minValue).takeIf { it > 0.0 } ?: 1.0
        val stepX = size.width / (values.size - 1)
        val bottom = size.height * 0.92f
        val usable = size.height * 0.8f

        drawLine(
            color = axisColor,
            start = Offset(0f, bottom),
            end = Offset(size.width, bottom),
            strokeWidth = 2f
        )

        fun yFor(value: Double) =
            bottom - ((value - minValue) / range * usable).toFloat()

        val path = Path()
        values.forEachIndexed { index, value ->
            val x = index * stepX
            val y = yFor(value)
            if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }

        clipRect(right = size.width * reveal) {
            drawPath(path, color = lineColor, style = Stroke(width = 5f, cap = StrokeCap.Round))
            values.forEachIndexed { index, value ->
                drawCircle(
                    color = lineColor,
                    radius = 5f,
                    center = Offset(index * stepX, yFor(value))
                )
            }
        }
    }
}

@Composable
private fun BarChart(values: List<Double>, reveal: Float, modifier: Modifier = Modifier) {
    val barColor = MaterialTheme.colorScheme.tertiary
    val emptyColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.15f)

    Canvas(modifier) {
        if (values.isEmpty()) return@Canvas

        val maxValue = (values.maxOrNull() ?: 0.0).takeIf { it > 0.0 } ?: 1.0
        val slot = size.width / values.size
        val barWidth = slot * 0.55f

        values.forEachIndexed { index, value ->
            val height = (value / maxValue * size.height * 0.9 * reveal).toFloat()
            val left = index * slot + (slot - barWidth) / 2

            drawRoundRect(
                color = if (value > 0.0) barColor else emptyColor,
                topLeft = Offset(left, size.height - height),
                size = Size(barWidth, height.coerceAtLeast(3f)),
                cornerRadius = CornerRadius(6f, 6f)
            )
        }
    }
}
