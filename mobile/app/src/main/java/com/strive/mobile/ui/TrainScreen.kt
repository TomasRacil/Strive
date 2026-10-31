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
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.strive.mobile.data.Engine
import kotlinx.coroutines.delay

@Composable
fun TrainScreen(state: AppState) {
    val lang = state.settings.lang
    val unit = state.settings.unit
    fun t(key: String) = Strings.t(lang, key)

    // The picker lists lifts in engine order - least-loaded muscles first - so
    // the default selection is something the user can actually train today.
    // Keyed on the history so it reshuffles between sessions; it is stable during
    // one, because an open session is not written to `sessions` until it ends and
    // the chip must not move out from under a finger.
    val ordered = remember(state.exercises, state.sessions) { state.rankedExercises() }

    var exerciseIndex by remember { mutableIntStateOf(0) }
    var weightDisplay by remember { mutableDoubleStateOf(0.0) }
    var reps by remember { mutableIntStateOf(8) }
    var rir by remember { mutableIntStateOf(2) }

    // Rest is held as the instant it ends, not as a countdown: a counter loses
    // its place on recomposition and stops advancing while the app is in the
    // background, while an end time is still right when the user comes back.
    var restEndsAt by remember { mutableStateOf<Long?>(null) }
    var clockNow by remember { mutableLongStateOf(System.currentTimeMillis()) }

    val exercise = ordered.getOrNull(exerciseIndex)

    // Deleting the last lift (or editing the list mid-session) must not crash.
    if (exercise == null) {
        Column(Modifier.fillMaxSize().padding(20.dp)) {
            Text(t("train.title"), fontSize = 28.sp, fontWeight = FontWeight.ExtraBold)
            Spacer(Modifier.height(14.dp))
            Text(Strings.t(lang, "ex.empty"), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        return
    }

    // Recomputed when the lift, the history or the profile's body mass changes -
    // never per frame, because the engine walks the whole history.
    val advice = remember(exercise.id, state.sessions, state.settings.bodyKg) {
        state.loadAdvice(exercise.id)
    }
    val targetSets = remember(exercise.id, state.sessions) { state.targetSets(exercise.id) }

    // Re-seed the inputs whenever the lift or the unit changes, so the stepper
    // starts from the advice: the load and the rep target move together, and a
    // jump in load comes with a lower target.
    LaunchedEffect(exercise.id, advice, unit) {
        weightDisplay = Format.toDisplay(advice.weightKg, unit)
        reps = advice.targetReps
    }

    // Tick from the clock rather than by subtracting: the remainder is derived
    // from restEndsAt on every pass, so a clock jump cannot leave it stuck or
    // negative. The loop stops itself the moment the rest is over.
    LaunchedEffect(restEndsAt) {
        val endsAt = restEndsAt ?: return@LaunchedEffect
        while (RestClock.remainingSeconds(endsAt, System.currentTimeMillis()) > 0) {
            clockNow = System.currentTimeMillis()
            delay(250)
        }
        clockNow = System.currentTimeMillis()
        restEndsAt = null
    }

    val restRemaining = RestClock.remainingSeconds(restEndsAt, clockNow)
    // The phone has no heart rate strap, so the two HR slots are null and the
    // engine returns the base length. This call is where a strap would plug in.
    val restSeconds = Engine.rest(exercise.restSeconds, null, null).seconds

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
            ordered.forEachIndexed { index, ex ->
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
                        // Load and target reps together: they are one decision,
                        // and showing the weight alone hides that a heavier set
                        // is meant to be taken for fewer reps.
                        Text(
                            "${t("train.suggested")}: " +
                                "${Format.weight(advice.weightKg, unit)} × ${advice.targetReps}",
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
                restEndsAt = System.currentTimeMillis() + restSeconds * 1000L
            },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(t("train.logSet"))
        }

        if (restEndsAt != null) {
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
                    OutlinedButton(onClick = { restEndsAt = null }) { Text(t("train.skip")) }
                }
            }
        }

        // ---- sets logged this session ----
        val logged = active.sets.count { it.exerciseId == exercise.id }
        // Progress towards the engine's set target: a muscle with a light week
        // gets a fourth set, a lift never done stays at three.
        Text(
            "${Strings.sets(lang, logged)} / $targetSets",
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
                restEndsAt = null
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
