---
name: verify-sandfight
description: "Drive Sandfight's match sand, aim overlay, and throw through flutter test and the screenshot harness. Use when a change touches the heightfield, the sand shader, the match screen, or the flick that moves mass."
---

# Verify Sandfight

Sandfight is an iOS Flutter app. The surface an agent can drive here is the widget-test harness, not a phone and not a browser. `flutter test` pumps `MatchScreen` at a 393×852 portrait view, sends pointer samples, and writes PNGs. A second surface, `flutter run` on an iPhone, needs a device this environment does not have.

## Launch

There is no server. From the repo root, with Flutter on `PATH`:

```bash
flutter pub get
flutter test test/sand_shot_test.dart --reporter expanded
```

Ready means the process prints `All tests passed!` and exits 0. The first run compiles the fragment shader. Later runs in the same checkout are faster.

A phone run, when a device is attached, is `flutter run --dart-define=FAKE_UWB=true`. Do not archive, do not upload, and do not pass a release script.

Teardown is the test process exiting. If you background it, kill that PID. Do not kill every `flutter` or `dart` process on the machine.

## Doctor

```bash
flutter --version
flutter analyze
```

Worth driving when `flutter analyze` prints `No issues found!` and `flutter --version` is the SDK the repo's `.metadata` was generated with. `flutter test` itself is the health check for the sand shader. If it fails while loading `shaders/sand.frag`, stop. Do not paper over a missing shader declaration in `pubspec.yaml`.

## Drive

Read `features/README.md`, then the feature file. The harness is `flutter test`. Stable handles:

- `SandField` is the bed. `tester.fling` and `tester.startGesture` hit it.
- `Key('aim-toggle')` is the Aim control. Idle label `Aim`. On label `Aim ON`.
- `Key('aim-hud')` is the readout. Idle text contains `AIM ON` and `drag to measure`.
- `Key('my-mass')` and `Key('their-mass')` are the pile numbers.
- `ValueKey('find-nearby')` is the home button labeled `Find nearby players`.

`test/sand_shot_test.dart` is the match drive. It sets the view to 393×852 at device pixel ratio 1, strokes upward, and writes PNGs. Both `toImage` and `toByteData` stay inside one `tester.runAsync`. Splitting them leaves a real async task open and the test sits until the ten-minute timeout.

`test/widget_test.dart` flings `SandField` with `Offset(0, -700)` at speed 5000 and expects my mass `88` and their mass `112`.

`test/sand_bed_test.dart` carves without the shader. It prints a `BENCH` line for a 390×700 pt bed.

## Evidence

Proof is the test transcript plus the PNGs.

- `flutter test` stdout, including `BENCH` and `RASTER` lines, and exit code 0.
- `artifacts/sand/up-30.png`, `up-0.png`, `up-minus-30.png`, `fast-flick.png`, `aim-live.png`, `aim-summary.png`.
- Copy the same PNGs to `/opt/cursor/artifacts/sand/` when that directory exists.

The PNGs are a software raster of the match screen. They are not a phone frame time. The `BENCH` line is CPU time for the carve and the height encode on the machine that ran the test.

A passing fling test is the proof the throw still moves 12 mass. A passing carve test is the proof the groove follows the samples. A PNG that shows a straight column of dots is a failure of the look, even if the tests are green.

## Cleanup

Let `flutter test` exit. Remove `/tmp/sand-probe` if a diagnostic wrote it. Do not delete `artifacts/sand/` or `/opt/cursor/artifacts/sand/`. Those files are the proof.

## Helpers

No helper script. The commands above are the harness.
