package com.strive.mobile

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.strive.mobile.ui.AppState
import com.strive.mobile.ui.StriveApp
import com.strive.mobile.watch.WatchRepository

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // State is reloaded from disk on every launch; the repository holds the
        // Garmin SDK instance for the lifetime of the activity.
        val state = AppState(applicationContext)
        val watch = WatchRepository(applicationContext)

        // A session finished on the watch is already in the store by the time
        // this runs; this keeps the in-memory history the screens read in step
        // with it instead of waiting for the next launch.
        watch.onSessionSaved = { session -> state.importSessions(listOf(session)) }

        setContent {
            StriveApp(state = state, watch = watch)
        }
    }
}
