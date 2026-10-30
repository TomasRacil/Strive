package com.strive.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.strive.mobile.data.Exercise
import com.strive.mobile.data.Muscles

@Composable
fun ExerciseDetailScreen(
    exercise: Exercise,
    state: AppState,
    onBack: () -> Unit,
    onEdit: () -> Unit
) {
    val lang = state.settings.lang
    fun t(key: String) = Strings.t(lang, key)

    var showAddVariation by remember { mutableStateOf(false) }

    val loads = exercise.loadByMuscle()
    val peak = exercise.peakLoad()
    val ranked = loads.entries.sortedByDescending { it.value }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("← " + t("ex.title")) }
            Spacer(Modifier.weight(1f))
            TextButton(onClick = onEdit) { Text(t("ex.edit")) }
        }

        Text(exercise.name, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold)
        Text(
            "${exercise.muscle} · ${exercise.targetReps} reps · ${exercise.restSeconds}s",
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        if (exercise.description.isNotBlank()) {
            Text(exercise.description, fontSize = 14.sp, lineHeight = 20.sp)
        }

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp)) {
                Text(t("ex.muscleMap"), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
                if (loads.isEmpty()) {
                    Text(
                        t("ex.noMuscles"),
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    BodyMap(loads = loads, peak = peak)
                }
            }
        }

        if (ranked.isNotEmpty()) {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Text(t("ex.musclesWorked"), fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Spacer(Modifier.height(10.dp))

                    ranked.forEach { (muscleId, load) ->
                        val share = (load / peak).coerceIn(0.0, 1.0).toFloat()
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                Muscles.name(muscleId),
                                fontSize = 12.sp,
                                modifier = Modifier.weight(1f)
                            )
                            Box(
                                Modifier
                                    .weight(1f)
                                    .height(6.dp)
                                    .background(
                                        MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.15f),
                                        RoundedCornerShape(3.dp)
                                    )
                            ) {
                                Box(
                                    Modifier
                                        .fillMaxHeight()
                                        .fillMaxWidth(share)
                                        .background(
                                            MaterialTheme.colorScheme.primary,
                                            RoundedCornerShape(3.dp)
                                        )
                                )
                            }
                            Text(
                                "${(share * 100).toInt()}%",
                                fontSize = 11.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(start = 8.dp)
                            )
                        }
                    }
                }
            }
        }

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(t("ex.variations"), fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Spacer(Modifier.weight(1f))
                    TextButton(onClick = { showAddVariation = true }) {
                        Text(t("ex.addVariation"), fontSize = 12.sp)
                    }
                }

                if (exercise.variations.isEmpty()) {
                    Text(
                        t("ex.noVariations"),
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                exercise.variations.forEach { variation ->
                    Column(Modifier.padding(vertical = 6.dp)) {
                        Text(variation.name, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                        if (variation.note.isNotBlank()) {
                            Text(
                                variation.note,
                                fontSize = 11.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        val detail = buildList {
                            variation.targetReps?.let { add("$it reps") }
                            variation.restSeconds?.let { add("${it}s rest") }
                        }.joinToString(" · ")
                        if (detail.isNotBlank()) {
                            Text(
                                detail,
                                fontSize = 11.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
        }
    }

    if (showAddVariation) {
        AddVariationDialog(
            onDismiss = { showAddVariation = false },
            onSave = { name, note ->
                state.addVariation(exercise.id, name, note)
                showAddVariation = false
            },
            title = t("ex.addVariation"),
            nameLabel = t("ex.name"),
            noteLabel = t("ex.note"),
            saveLabel = t("ex.save"),
            cancelLabel = t("ex.cancel")
        )
    }
}

@Composable
private fun AddVariationDialog(
    onDismiss: () -> Unit,
    onSave: (String, String) -> Unit,
    title: String,
    nameLabel: String,
    noteLabel: String,
    saveLabel: String,
    cancelLabel: String
) {
    var name by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(nameLabel) },
                    singleLine = true
                )
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text(noteLabel) }
                )
            }
        },
        confirmButton = {
            TextButton(
                enabled = name.isNotBlank(),
                onClick = { onSave(name.trim(), note.trim()) }
            ) { Text(saveLabel) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(cancelLabel) }
        }
    )
}
