package com.strive.mobile.ui

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import com.strive.mobile.watch.WatchRepository

@Composable
fun StriveApp(state: AppState, watch: WatchRepository) {
    var tab by rememberSaveable { mutableStateOf("home") }
    val lang = state.settings.lang
    fun t(key: String) = Strings.t(lang, key)

    // Status bar icons have to contrast with what Compose actually draws, not
    // with the launch theme. Without this the clock is white on a light screen.
    val view = LocalView.current
    val dark = when (state.settings.theme) {
        "dark" -> true
        "light" -> false
        else -> isSystemInDarkTheme()
    }
    SideEffect {
        val window = (view.context as? Activity)?.window ?: return@SideEffect
        WindowCompat.getInsetsController(window, view).apply {
            isAppearanceLightStatusBars = !dark
            isAppearanceLightNavigationBars = !dark
        }
    }

    StriveTheme(state.settings.theme) {
        Scaffold(
            bottomBar = {
                NavigationBar {
                    NavItem("home", tab, t("nav.home"), Icons.Filled.Home) { tab = it }
                    NavItem("train", tab, t("nav.train"), Icons.Filled.PlayArrow) { tab = it }
                    NavItem("exercises", tab, t("nav.exercises"), Icons.Filled.List) { tab = it }
                    NavItem("history", tab, t("nav.history"), Icons.Filled.DateRange) { tab = it }
                    NavItem("settings", tab, t("nav.settings"), Icons.Filled.Settings) { tab = it }
                }
            }
        ) { padding ->
            Box(
                Modifier
                    .fillMaxSize()
                    .padding(padding)
            ) {
                when (tab) {
                    "home" -> HomeScreen(state) { tab = "train" }
                    "train" -> TrainScreen(state)
                    "exercises" -> ExercisesScreen(state)
                    "history" -> HistoryScreen(state)
                    else -> SettingsScreen(state, watch)
                }
            }
        }

        val finished = state.lastFinished
        if (finished != null) {
            AlertDialog(
                onDismissRequest = { state.dismissSummary() },
                title = { Text(t("train.summary")) },
                text = {
                    Text(
                        "${Strings.sets(lang, finished.sets.size)} · " +
                            Format.volume(finished.volumeKg, state.settings.unit)
                    )
                },
                confirmButton = {
                    TextButton(onClick = { state.dismissSummary() }) { Text("OK") }
                }
            )
        }
    }
}

// NavigationBarItem is a RowScope extension, so this helper must be one too -
// otherwise the call does not resolve at all.
@Composable
private fun RowScope.NavItem(
    id: String,
    current: String,
    label: String,
    icon: ImageVector,
    onSelect: (String) -> Unit
) {
    NavigationBarItem(
        selected = current == id,
        onClick = { onSelect(id) },
        icon = { Icon(icon, contentDescription = label) },
        label = { Text(label, style = MaterialTheme.typography.labelSmall) }
    )
}
