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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

@Composable
fun TrainScreen(state: AppState) {
    val lang = state.settings.lang
    val unit = state.settings.unit
    fun t(key: String) = Strings.t(lang, key)

    var exerciseIndex by remember { mutableIntStateOf(0) }
    var weightDisplay by remember { mutableDoubleStateOf(0.0) }
    var reps by remember { mutableIntStateOf(8) }
    var rir by remember { mutableIntStateOf(2) }
    var restRemaining by remember { mutableIntStateOf(0) }

    // Re-seed the inputs whenever the lift or the unit changes, so the stepper
    // starts from the suggested load rather than a stale number.
    LaunchedEffect(exerciseIndex, unit) {
        val ex = state.exercises[exerciseIndex]
        weightDisplay = Format.toDisplay(state.suggestedWeight(ex.id), unit)
        reps = ex.targetReps
    }

    LaunchedEffect(restRemaining > 0) {
        while (restRemaining > 0) {
            delay(1000)
            restRemaining -= 1
        }
    }

    val exercise = state.exercises[exerciseIndex]
    val active = state.active

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Text(t("train.title"), fontSize = 28.sp, fontWeight = FontWeight.ExtraBold)

        if (active == null) {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(20.dp)) {
                    Text(t("train.startHint"), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(14.dp))
                    Button(onClick = { state.startSession() }, modifier = Modifier.fillMaxWidth()) {
                        Text(t("home.start"))
                    }
                }
            }
            return@Column
        }

        // ---- lift selector ----
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            state.exercises.forEachIndexed { index, ex ->
                FilterChip(
                    selected = index == exerciseIndex,
                    onClick = { exerciseIndex = index },
                    label = { Text(ex.name) }
                )
            }
        }

        // ---- load ----
        Card(Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(t("train.weight"), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OutlinedButton(onClick = {
                        weightDisplay = (weightDisplay - Format.step(unit)).coerceAtLeast(0.0)
                    }) { Text("−", fontSize = 20.sp) }

                    Column(
                        modifier = Modifier.weight(1f),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(
                            Format.weight(Format.toKg(weightDisplay, unit), unit),
                            fontSize = 34.sp,
                            fontWeight = FontWeight.ExtraBold,
                            color = MaterialTheme.colorScheme.primary
                        )
                        Text(
                            "${t("train.suggested")}: ${Format.weight(state.suggestedWeight(exercise.id), unit)}",
                            fontSize = 11.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }

                    OutlinedButton(onClick = { weightDisplay += Format.step(unit) }) {
                        Text("+", fontSize = 20.sp)
                    }
                }
            }
        }

        // ---- reps and RIR ----
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StepperCard(
                label = t("train.reps"),
                value = reps.toString(),
                onMinus = { reps = (reps - 1).coerceAtLeast(1) },
                onPlus = { reps += 1 },
                modifier = Modifier.weight(1f)
            )
            StepperCard(
                label = t("train.rir"),
                value = rir.toString(),
                onMinus = { rir = (rir - 1).coerceAtLeast(0) },
                onPlus = { rir = (rir + 1).coerceAtMost(5) },
                modifier = Modifier.weight(1f)
            )
        }

        Button(
            onClick = {
                state.logSet(exercise, Format.toKg(weightDisplay, unit), reps, rir)
                restRemaining = exercise.restSeconds
            },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(t("train.logSet"))
        }

        if (restRemaining > 0) {
            Card(Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier.padding(20.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(t("train.rest"), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(
                            "%d:%02d".format(restRemaining / 60, restRemaining % 60),
                            fontSize = 30.sp,
                            fontWeight = FontWeight.ExtraBold,
                            color = MaterialTheme.colorScheme.tertiary
                        )
                    }
                    OutlinedButton(onClick = { restRemaining = 0 }) { Text(t("train.skip")) }
                }
            }
        }

        // ---- sets logged this session ----
        val logged = active.sets.count { it.exerciseId == exercise.id }
        Text(
            "$logged ${t("train.sets")}",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 13.sp
        )

        active.sets.filter { it.exerciseId == exercise.id }.forEach { set ->
            Text(
                "${Format.weight(set.weightKg, unit)} × ${set.reps}" +
                    (set.rir?.let { "  ·  RIR $it" } ?: ""),
                fontSize = 14.sp
            )
        }

        Spacer(Modifier.height(6.dp))

        OutlinedButton(
            onClick = {
                restRemaining = 0
                state.finishSession()
            },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(t("train.finish"))
        }
    }
}

@Composable
private fun StepperCard(
    label: String,
    value: String,
    onMinus: () -> Unit,
    onPlus: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(modifier) {
        Column(
            modifier = Modifier.padding(14.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(label, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, fontSize = 24.sp, fontWeight = FontWeight.Bold)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onMinus) { Text("−") }
                OutlinedButton(onClick = onPlus) { Text("+") }
            }
        }
    }
}
