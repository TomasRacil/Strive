package com.strive.mobile.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.strive.mobile.data.Exercise

@Composable
fun ExercisesScreen(state: AppState) {
    val lang = state.settings.lang
    fun t(key: String) = Strings.t(lang, key)

    var showDialog by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<Exercise?>(null) }
    var detailId by remember { mutableStateOf<String?>(null) }

    // Look the lift up rather than holding it, so editing it updates the detail
    // view underneath instead of showing a stale copy.
    val detail = detailId?.let { id -> state.exercises.firstOrNull { it.id == id } }

    if (detail != null) {
        ExerciseDetailScreen(
            exercise = detail,
            state = state,
            onBack = { detailId = null },
            onEdit = {
                editing = detail
                showDialog = true
            }
        )
    } else {

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(20.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(t("ex.title"), fontSize = 28.sp, fontWeight = FontWeight.ExtraBold)
            Spacer(Modifier.weight(1f))
            Button(onClick = {
                editing = null
                showDialog = true
            }) {
                Text(t("ex.add"), fontSize = 13.sp)
            }
        }

        Spacer(Modifier.height(14.dp))

        if (state.exercises.isEmpty()) {
            Text(t("ex.empty"), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(state.exercises) { exercise ->
                Card(
                    Modifier
                        .fillMaxWidth()
                        .clickable { detailId = exercise.id }
                ) {
                    Row(
                        modifier = Modifier.padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(exercise.name, fontWeight = FontWeight.Bold)
                            Text(
                                "${exercise.muscle} · ${exercise.targetReps} reps · ${exercise.restSeconds}s",
                                fontSize = 12.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        TextButton(onClick = { state.deleteExercise(exercise.id) }) {
                            Text(t("ex.delete"), fontSize = 12.sp)
                        }
                    }
                }
            }
        }
    }
    }

    if (showDialog) {
        ExerciseDialog(
            initial = editing,
            labels = ExerciseDialogLabels(
                add = t("ex.add"),
                edit = t("ex.edit"),
                name = t("ex.name"),
                muscle = t("ex.muscle"),
                reps = t("ex.reps"),
                rest = t("ex.rest"),
                save = t("ex.save"),
                cancel = t("ex.cancel")
            ),
            onDismiss = { showDialog = false },
            onSave = { name, muscle, reps, rest ->
                val current = editing
                if (current == null) {
                    state.addExercise(name, muscle, reps, rest)
                } else {
                    state.updateExercise(
                        current.copy(
                            name = name,
                            muscle = muscle,
                            targetReps = reps,
                            restSeconds = rest
                        )
                    )
                }
                showDialog = false
            }
        )
    }
}

private data class ExerciseDialogLabels(
    val add: String,
    val edit: String,
    val name: String,
    val muscle: String,
    val reps: String,
    val rest: String,
    val save: String,
    val cancel: String
)

@Composable
private fun ExerciseDialog(
    initial: Exercise?,
    labels: ExerciseDialogLabels,
    onDismiss: () -> Unit,
    onSave: (String, String, Int, Int) -> Unit
) {
    var name by remember { mutableStateOf(initial?.name ?: "") }
    var muscle by remember { mutableStateOf(initial?.muscle ?: "") }
    var reps by remember { mutableStateOf((initial?.targetReps ?: 8).toString()) }
    var rest by remember { mutableStateOf((initial?.restSeconds ?: 120).toString()) }

    val valid = name.isNotBlank() && (reps.toIntOrNull() ?: 0) > 0 && (rest.toIntOrNull() ?: -1) >= 0

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (initial == null) labels.add else labels.edit) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(labels.name) },
                    singleLine = true
                )
                OutlinedTextField(
                    value = muscle,
                    onValueChange = { muscle = it },
                    label = { Text(labels.muscle) },
                    singleLine = true
                )
                OutlinedTextField(
                    value = reps,
                    onValueChange = { reps = it.filter { c -> c.isDigit() } },
                    label = { Text(labels.reps) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                )
                OutlinedTextField(
                    value = rest,
                    onValueChange = { rest = it.filter { c -> c.isDigit() } },
                    label = { Text(labels.rest) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                )
            }
        },
        confirmButton = {
            TextButton(
                enabled = valid,
                onClick = {
                    onSave(
                        name.trim(),
                        muscle.trim().ifBlank { "Other" },
                        reps.toIntOrNull() ?: 8,
                        rest.toIntOrNull() ?: 120
                    )
                }
            ) {
                Text(labels.save)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(labels.cancel) }
        }
    )
}
