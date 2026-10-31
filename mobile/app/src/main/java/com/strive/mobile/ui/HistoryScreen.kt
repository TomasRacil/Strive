package com.strive.mobile.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.strive.mobile.data.Exercise
import com.strive.mobile.data.Session
import kotlin.math.round

@Composable
fun HistoryScreen(state: AppState) {
    val lang = state.settings.lang
    val unit = state.settings.unit
    fun t(key: String) = Strings.t(lang, key)

    var mode by remember { mutableStateOf("sessions") }
    var openSession by remember { mutableStateOf<Session?>(null) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(t("history.title"), fontSize = 28.sp, fontWeight = FontWeight.ExtraBold)

        // Sessions and progress are two views of the same history, so they share
        // a tab rather than taking another slot in the bottom bar.
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = mode == "sessions",
                onClick = { mode = "sessions" },
                label = { Text(t("hist.sessions")) }
            )
            FilterChip(
                selected = mode == "progress",
                onClick = { mode = "progress" },
                label = { Text(t("hist.progress")) }
            )
        }

        if (mode == "progress") {
            ProgressView(state)
            return@Column
        }

        if (state.sessions.isEmpty()) {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(20.dp)) {
                    Text(t("history.empty"), fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(4.dp))
                    Text(
                        t("history.emptyHint"),
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        state.sessions.forEach { session ->
            SessionCard(
                session = session,
                // Compared against the whole history rather than only the cards
                // drawn so far, so a card does not change as the list scrolls.
                progress = Stats.liftProgress(session, state.sessions),
                lifts = Stats.topLifts(session, 3),
                exercises = state.exercises,
                bodyKg = state.settings.bodyKg,
                lang = lang,
                unit = unit,
                onOpen = { openSession = session },
                onDelete = { state.deleteSession(session.id) }
            )
        }

        // Tapping a session shows what was actually lifted, grouped by exercise.
        openSession?.let { session ->
            AlertDialog(
                onDismissRequest = { openSession = null },
                confirmButton = {
                    TextButton(onClick = { openSession = null }) {
                        Text(if (lang == "cs") "Zavřít" else "Close")
                    }
                },
                title = { Text(Format.date(session.startedAt, lang)) },
                text = {
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .verticalScroll(rememberScrollState())
                    ) {
                        Text(
                            "${Strings.sets(lang, session.sets.size)} · " +
                                "${Format.volume(session.volumeKg(state.exercises, state.settings.bodyKg), unit)} · " +
                                Format.duration(session.durationSeconds),
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )

                        session.sets
                            .groupBy { it.exerciseId }
                            .forEach { (_, sets) ->
                                Text(
                                    sets.first().exerciseName,
                                    fontWeight = FontWeight.Bold,
                                    modifier = Modifier.padding(top = 12.dp, bottom = 4.dp)
                                )
                                sets.forEachIndexed { index, entry ->
                                    val timing =
                                        if (entry.durationSeconds > 0) "   ${entry.durationSeconds}s" else ""
                                    Text(
                                        "${index + 1}.  ${Format.weight(entry.weightKg, unit)} × ${entry.reps}$timing",
                                        fontSize = 13.sp
                                    )
                                }
                            }
                    }
                }
            )
        }
    }
}

/**
 * One past workout. The top row is what the card always showed; underneath, the
 * session's main lift is compared with the last session that trained it, which
 * is the question the history tab exists to answer.
 */
@Composable
private fun SessionCard(
    session: Session,
    progress: Stats.LiftProgress?,
    lifts: List<String>,
    exercises: List<Exercise>,
    bodyKg: Double,
    lang: String,
    unit: String,
    onOpen: () -> Unit,
    onDelete: () -> Unit
) {
    Card(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen)
    ) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(Format.date(session.startedAt, lang), fontWeight = FontWeight.Bold)
                    Text(
                        "${Strings.sets(lang, session.sets.size)} · " +
                            "${Format.volume(session.volumeKg(exercises, bodyKg), unit)} · " +
                            Format.duration(session.durationSeconds),
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                TextButton(onClick = onDelete) {
                    Text(Strings.t(lang, "history.delete"))
                }
            }

            if (progress != null) {
                Spacer(Modifier.height(10.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            progress.exerciseName,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            "${Format.weight(progress.bestKg, unit)} · " +
                                Strings.t(lang, "history.bestSet"),
                            fontSize = 11.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1
                        )
                    }

                    // A trend needs two points; a single session has none.
                    if (progress.history.size >= 2) {
                        Sparkline(
                            values = progress.history,
                            modifier = Modifier
                                .width(52.dp)
                                .height(22.dp)
                        )
                        Spacer(Modifier.width(8.dp))
                    }

                    ProgressBadge(
                        deltaKg = progress.deltaKg,
                        unit = unit,
                        firstTimeLabel = Strings.t(lang, "history.firstTime"),
                        sameLabel = Strings.t(lang, "history.same")
                    )
                }
            }

            if (lifts.isNotEmpty()) {
                Spacer(Modifier.height(10.dp))
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    lifts.forEach { name -> LiftChip(name) }
                }
            }
        }
    }
}

/** A lift name as a quiet label, so a session is recognisable without opening it. */
@Composable
private fun LiftChip(name: String) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
        shape = RoundedCornerShape(50)
    ) {
        Text(
            name,
            fontSize = 11.sp,
            maxLines = 1,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)
        )
    }
}

/**
 * "+2.5 kg" in green, "-5.0 kg" in red, and a quiet label when there is nothing
 * to compare against. The difference is rounded in the display unit, so a pound
 * user never sees noise from the kg round-trip.
 */
@Composable
private fun ProgressBadge(
    deltaKg: Double?,
    unit: String,
    firstTimeLabel: String,
    sameLabel: String
) {
    val shown = deltaKg?.let { round(Format.toDisplay(it, unit) * 10.0) / 10.0 }

    val color = when {
        shown == null -> MaterialTheme.colorScheme.onSurfaceVariant
        shown > 0.0 -> gainColor()
        shown < 0.0 -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }

    val label = when {
        shown == null -> firstTimeLabel
        shown == 0.0 -> sameLabel
        else -> {
            val text = Format.weight(Format.toKg(shown, unit), unit)
            if (shown > 0.0) "+$text" else text
        }
    }

    Surface(
        color = color.copy(alpha = 0.12f),
        contentColor = color,
        shape = RoundedCornerShape(50)
    ) {
        Text(
            label,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp)
        )
    }
}

// The palette has no success colour, so pick a green that keeps its contrast on
// both the light and the dark surface instead of hard-coding one.
private val GainGreenLight = Color(0xFF15803D)
private val GainGreenDark = Color(0xFF4ADE80)

@Composable
private fun gainColor(): Color =
    if (MaterialTheme.colorScheme.surface.luminance() < 0.5f) GainGreenDark else GainGreenLight

/**
 * The main lift's best set across recent sessions, drawn the way the progress
 * tab draws its line chart, only smaller and without axes.
 */
@Composable
private fun Sparkline(values: List<Double>, modifier: Modifier = Modifier) {
    val lineColor = MaterialTheme.colorScheme.primary

    Canvas(modifier) {
        if (values.size < 2) return@Canvas

        val minValue = values.min()
        val maxValue = values.max()
        val flat = maxValue - minValue <= 0.0
        val range = if (flat) 1.0 else maxValue - minValue

        // Inset by the dot radius so the last point is not clipped by the edge.
        val inset = 3.5f
        val stepX = (size.width - inset * 2) / (values.size - 1)
        val top = inset
        val usable = size.height - inset * 2

        fun yFor(value: Double): Float {
            if (flat) return size.height / 2f
            return (top + usable - ((value - minValue) / range * usable)).toFloat()
        }

        fun xFor(index: Int): Float = inset + index * stepX

        val path = Path()
        values.forEachIndexed { index, value ->
            if (index == 0) path.moveTo(xFor(index), yFor(value))
            else path.lineTo(xFor(index), yFor(value))
        }

        drawPath(path, color = lineColor, style = Stroke(width = 3f, cap = StrokeCap.Round))
        drawCircle(
            color = lineColor,
            radius = 3.5f,
            center = Offset(xFor(values.lastIndex), yFor(values.last()))
        )
    }
}
