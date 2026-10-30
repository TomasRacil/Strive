package com.strive.mobile.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
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

        state.sessions.forEach { session ->
            Card(Modifier.fillMaxWidth()) {
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
    }
}
