# Strive watch app (Connect IQ / Monkey C)

A sideloaded watch app that puts the *recommended* weight on your wrist and logs
sets without a phone.

## Controls

    middle-left     load +2.5 kg
    bottom-left     load −2.5 kg
    top-right       log a set
    bottom-right    next exercise

    tap left third      load −2.5 kg
    tap right third     load +2.5 kg
    tap middle          weight wheel — scroll to any load in 2.5 kg steps
    swipe up            log a set
    swipe left/right    next / previous exercise

Buttons are kept first-class on purpose: gloves and sweaty hands make the
touchscreen unreliable exactly when you need to log a set.

## What it does

- One screen per exercise: recommended load, target reps, sets logged this session.
- UP / DOWN adjust the load by 2.5 kg, SELECT logs a set, BACK moves to the next
  exercise.
- The recommendation is double progression: repeat the load until you complete
  three sets, then it adds 2.5 kg next time. State is kept on the watch itself.

## What it cannot do

- **It cannot read your Garmin Connect history or workouts.** There is no API for
  that from the watch. The app starts from zero and keeps its own record per
  exercise. Your Strive history on the phone is not visible to it.
- It does not record a FIT activity yet. That is the next step and needs
  `ActivityRecording` verified against the installed SDK.
- The exercise list is compiled in (`source/Exercises.mc`). A sideloaded app
  cannot rely on settings pushed through Garmin Connect Mobile, so changing the
  list means editing that file and rebuilding.

## Prerequisites

1. **JDK 21** — `winget install --id EclipseAdoptium.Temurin.21.JDK -e`
2. **Connect IQ SDK** — download `sdkmanager.exe` from
   <https://developer.garmin.com/connect-iq/sdk/>, run it, sign in with your
   Garmin account, accept the agreement, and install the SDK plus your device.
   There is no direct download; the SDK is gated behind this GUI.

## Build

```powershell
cd garmin\watch
.\build.ps1
```

Defaults to `fenix8pro47mm` and reads the active SDK path from
`%APPDATA%\Garmin\ConnectIQ\current-sdk.cfg`, so it keeps working after an SDK
update. Output: `build\Strive-fenix8pro47mm.prg`.

The device id must also be listed in `manifest.xml` under `<iq:products>`.
Device ids live in `%APPDATA%\Garmin\ConnectIQ\Devices\` — the folder names are
the ids.

Verified building against Connect IQ 9.3.0 for `fenix8pro47mm`.

## Sideload

1. Plug the watch in by USB. It mounts as a drive.
2. Copy `build\Strive-fenix8pro47mm.prg` into `GARMIN\APPS` on that drive.
3. Unplug. The app appears in the watch's app list.

Or in one step, if the watch is mounted at `E:`:

```powershell
.\build.ps1 -Deploy E:\
```

## Layout

```
manifest.xml              app id, device list, Fit permission
monkey.jungle             build config
source/StriveApp.mc       entry point
source/StriveView.mc      the screen
source/StriveDelegate.mc  button handling
source/Progress.mc        local per-exercise progression
source/Exercises.mc       compiled-in exercise list
keys/                     developer key (gitignored)
```
