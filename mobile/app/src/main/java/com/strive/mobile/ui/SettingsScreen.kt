package com.strive.mobile.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.strive.mobile.watch.WatchRepository

@Composable
fun SettingsScreen(state: AppState, watch: WatchRepository) {
    val lang = state.settings.lang
    val settings = state.settings
    fun t(key: String) = Strings.t(lang, key)

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Text(t("settings.title"), fontSize = 28.sp, fontWeight = FontWeight.ExtraBold)
        }

        item {
            SectionCard(t("settings.theme")) {
                ChipRow(
                    options = listOf(
                        "system" to t("settings.theme.system"),
                        "dark" to t("settings.theme.dark"),
                        "light" to t("settings.theme.light")
                    ),
                    selected = settings.theme,
                    onSelect = { state.updateSettings(settings.copy(theme = it)) }
                )
            }
        }

        item {
            SectionCard(t("settings.units")) {
                ChipRow(
                    options = listOf(
                        "kg" to t("settings.unit.kg"),
                        "lb" to t("settings.unit.lb")
                    ),
                    selected = settings.unit,
                    onSelect = { state.updateSettings(settings.copy(unit = it)) }
                )
            }
        }

        item {
            SectionCard(t("settings.language")) {
                ChipRow(
                    options = listOf("en" to "English", "cs" to "Čeština"),
                    selected = settings.lang,
                    onSelect = { state.updateSettings(settings.copy(lang = it)) }
                )
            }
        }

        item { WatchCard(state, watch, ::t) }

        item {
            SectionCard(t("settings.about")) {
                Text(
                    t("settings.aboutText"),
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(10.dp))
                Text(t("settings.privacy"), fontWeight = FontWeight.Bold, fontSize = 13.sp)
                Text(
                    t("settings.privacyText"),
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(10.dp))
                Text(
                    "${t("settings.version")} ${BuildInfo.VERSION}",
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun SectionCard(title: String, content: @Composable () -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Text(title, fontWeight = FontWeight.Bold, fontSize = 15.sp)
            Spacer(Modifier.height(10.dp))
            content()
        }
    }
}

@Composable
private fun ChipRow(
    options: List<Pair<String, String>>,
    selected: String,
    onSelect: (String) -> Unit
) {
    Row(
        modifier = Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        options.forEach { (value, label) ->
            FilterChip(
                selected = selected == value,
                onClick = { onSelect(value) },
                label = { Text(label) }
            )
        }
    }
}

@Composable
private fun WatchCard(state: AppState, watch: WatchRepository, t: (String) -> String) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Text(t("watch.title"), fontWeight = FontWeight.Bold, fontSize = 15.sp)
            Spacer(Modifier.height(6.dp))
            Text(
                t("watch.subtitle"),
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.height(12.dp))

            Button(
                onClick = {
                    watch.initialize()
                    watch.refreshDevices()
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(t("watch.search"))
            }

            Spacer(Modifier.height(10.dp))

            if (watch.devices.isEmpty()) {
                Text(
                    t("watch.none"),
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            watch.devices.forEach { device ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(device.name, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                        Text(
                            if (device.connected) t("watch.connected") else t("watch.notConnected"),
                            fontSize = 11.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    OutlinedButton(
                        enabled = device.connected,
                        onClick = {
                            watch.sendPlan(
                                deviceId = device.id,
                                items = state.exercises.map { it.id to state.suggestedWeight(it.id) }
                            )
                        }
                    ) {
                        Text(t("watch.send"), fontSize = 12.sp)
                    }
                }

                OutlinedButton(
                    enabled = device.connected,
                    onClick = { watch.openOnWatch(device.id) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Open Strive on the watch", fontSize = 12.sp)
                }
            }

            if (watch.status.isNotBlank()) {
                Spacer(Modifier.height(8.dp))
                Text(
                    watch.status,
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.primary
                )
            }

            watch.appStatus?.let { state ->
                Spacer(Modifier.height(8.dp))
                Text(
                    when (state) {
                        "installed" -> "Strive app on watch: installed"
                        "not_installed" -> "Strive app on watch: NOT installed — install it from the beta link"
                        else -> "Strive app on watch: unknown"
                    },
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

object BuildInfo {
    const val VERSION = "2.0.0"
}
