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

`JAVA_HOME` has the same trap: give it the native form
(`C:/Program Files/Eclipse Adoptium/jdk-21...`). An MSYS-style
`/c/Program Files/...` works until the Gradle daemon is cold, and then `gradlew`
fails with a confusing "no Java home" rather than a path error.

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

- **Nothing flows back automatically yet.** The channel is proven in both
  directions (see below), but the watch currently sends only a test message; the
  session log is not wired to it.
- Nothing here has been run on a physical device or watch yet. It compiles and
  packages; runtime behaviour is unverified.

### What is verified

Measured on a fenix 8 47mm + Pixel 9 Pro with `ciq-companion-app-sdk` 2.2.0, with
the watch paired as normal:

- **Phone → watch:** `sendMessage` returns `SUCCESS`, the watch's
  `onPhoneAppMessage` fires, and the payload drives the screen immediately (a
  planned weight appeared as 27.5 kg).
- **Watch → phone:** `Comm.transmit` from the watch arrives in
  `IQApplicationEventListener.onMessageReceived` within a second.

So `CIQQA-4631` (the message bus "accepts and never delivers") does not apply on
this firmware. Direct BLE was abandoned for this reason: it needs the watch's
Garmin Connect link torn down first, i.e. unpairing the phone before every sync.
The phone-side GATT server and its Settings probe card are gone with it, which is
why the app now declares no Bluetooth permission: the companion SDK hands every
message to Garmin Connect Mobile instead.
