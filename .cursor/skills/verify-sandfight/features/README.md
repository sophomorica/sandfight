# Sandfight verification map

This directory is the maintained source for verifying Sandfight's user-facing behavior from the widget-test harness. Read the index before driving, then use the matching feature file.

## Baseline preconditions

- Run from the repo root with Flutter on `PATH`.
- `flutter analyze` prints `No issues found!`.
- Do not start a second `flutter test` against the same checkout while one is compiling. They share `build/`.
- The match drive uses `LocalDrive` inside the test. It does not need Bluetooth, a second phone, or `FAKE_UWB`.
- Never treat a software-raster PNG as a phone frame-time measurement.

## Driving conventions

- Start from the feature file's preconditions.
- Prefer the keys named in the skill (`aim-toggle`, `aim-hud`, `my-mass`, `their-mass`, `find-nearby`, `SandField`).
- Keep `toImage` and `toByteData` inside one `tester.runAsync`.
- Leave `artifacts/sand/` in place after the run.

## Proof and skip reporting

- Capture the command, the transcript, and the exit code.
- Match-sand proof includes the six PNGs and a `RASTER` line per shot.
- Throw proof includes the mass numbers after the fling, not only a screenshot.
- Report a phone-only check as unreachable. Name the command that was not run and the missing device.

## Feature entry contract

Each feature file starts with an H1 and one paragraph, then exactly four H2 sections, in order: `Sub-features`, `How to get to it (user POV)`, `Driving it with flutter test`, `Gotchas`.

## Features

- [Match sand](./match-sand.md) covers the carved bed, the three upward angles, and the fast flick.
- [Aim overlay](./aim-overlay.md) covers the on/off label, the live readout, and the post-release summary.
- [Throw](./throw.md) covers the flick that moves 12 mass. The carve does not replace this.
- [Home](./home.md) covers the lobby line and the iPhone 12 floor.
