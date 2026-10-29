# Strive for Android (Kotlin)

The native phone app. It replaces the Capacitor wrapper as the primary app,
because the Connect IQ companion SDK is a JVM library that talks to Garmin
Connect Mobile over a bound service — something a WebView or PWA cannot reach.

The React app in `../src` still works as a web interface and is still deployed,
but it can never talk to the watch. This app can.

## Build

    # JDK 21 and the Android SDK are required
    export JAVA_HOME='C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot'
    cd mobile
    ./gradlew assembleDebug

The APK lands in `app/build/outputs/apk/debug/app-debug.apk`:

    package  com.strive.mobile
    minSdk   26
    target   36

`local.properties` holds the SDK path and is gitignored — use forward slashes
(`sdk.dir=C:/Users/you/AppData/Local/Android/Sdk`), because the backslash-escaped
form fails the Android SDK path validator.

## Layout

    data/    models, seed library, double progression, JSON persistence
    ui/      Compose screens, theme, units, translations
    watch/   Connect IQ companion bridge

## What it does

- Home: streak, session count, weekly volume, recent sessions
- Train: pick a lift, log sets with weight, reps and RIR, rest countdown, finish
- History: every session with volume and duration, deletable
- Settings: theme (system/dark/light), units (kg/lb), language (en/cs), about
- Watch: find paired watches, send the current plan to the watch app

Weights are stored in kilograms always. `Format` is the only place that knows
about pounds, so changing the unit never rewrites history.

## Watch bridge

`WatchRepository` uses `com.garmin.connectiq:ciq-companion-app-sdk` from Maven
Central. It sends a `Map` — which arrives on the watch as a `Dictionary` — with
this shape:

    {"type": "plan", "items": [{"id": "bench_press", "weight": 22.5}, ...]}

The watch app stores those weights in `Application.Storage` under `p_<id>` and
prefers them over its own progression guess.

The application id in `STRIVE_APP_ID` must match `iq:application id` in
`garmin/watch/manifest.xml`, or the message never arrives.

### Not yet done

- **Sets do not flow back from the watch.** `Communications.transmit` on the
  watch side has a stricter signature than the docs suggest (its third argument
  is a `ConnectionListener`, and the payload dictionary must match
  `TransmitType`). That needs a device to test against, so it is deliberately
  left out rather than guessed at.
- Nothing here has been run on a physical device or watch yet. It compiles and
  packages; runtime behaviour is unverified.
