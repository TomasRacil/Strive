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

        setContent {
            StriveApp(state = state, watch = watch)
        }
    }
}
