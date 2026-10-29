# Strive watch app (Connect IQ / Monkey C)

A sideloaded watch app that puts the *recommended* weight on your wrist and logs
sets without a phone.

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
.\build.ps1 -Device fenix7
```

The device id must also be listed in `manifest.xml` under `<iq:products>`.
`monkeyc --devices` prints the valid ids.

## Sideload

1. Plug the watch in by USB. It mounts as a drive.
2. Copy `build\Strive-<device>.prg` into `GARMIN\APPS` on that drive.
3. Unplug. The app appears in the watch's app list.

Or in one step: `.\build.ps1 -Device fenix7 -Deploy E:\`

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
