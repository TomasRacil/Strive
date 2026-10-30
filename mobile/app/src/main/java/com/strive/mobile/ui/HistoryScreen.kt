package com.strive.mobile.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import com.strive.mobile.data.Session
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun HistoryScreen(state: AppState) {
    val lang = state.settings.lang
    val unit = state.settings.unit
    fun t(key: String) = Strings.t(lang, key)

    var mode by remember { mutableStateOf("sessions") }

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
            Text(t("history.empty"), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        var openSession by remember { mutableStateOf<Session?>(null) }

        state.sessions.forEach { session ->
            Card(
                Modifier
                    .fillMaxWidth()
                    .clickable { openSession = session }
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(Format.date(session.startedAt, lang), fontWeight = FontWeight.Bold)
                        Text(
                            "${Strings.sets(lang, session.sets.size)} · " +
                                "${Format.volume(session.volumeKg, unit)} · " +
                                Format.duration(session.durationSeconds),
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    TextButton(onClick = { state.deleteSession(session.id) }) {
                        Text(t("history.delete"))
                    }
                }
            }
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
                                "${Format.volume(session.volumeKg, unit)} · " +
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
