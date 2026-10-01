# Aim overlay

Aim is a match control, off by default. On, it shows the stroke's direction, angle, and speed. Off, the sand is clear of that overlay.

## Sub-features

- `aim-off` shows a dark control labeled `Aim` and no readout.
- `aim-idle` shows a white control labeled `Aim ON` and a pill that says to drag.
- `aim-live` shows the angle and speed while the finger is down.
- `aim-summary` shows the average angle after release.

## How to get to it (user POV)

- During a match, tap the Aim control at the bottom center of the sand.
- Drag on the sand while it is on.
- Lift the finger and read the last stroke.

## Driving it with flutter test

Preconditions:

- `flutter analyze` is clean.
- The match-sand drive is the same test file. Run it once and read both results.

- **Toggle.** Run `flutter test test/sand_shot_test.dart --reporter expanded`. The test `aim on is labeled Aim ON and shows the measure hint` passes. It finds the text `Aim`, then `Aim ON`, and the hud contains `AIM ON` and `drag to measure`.
- **Live and summary.** The same run writes `artifacts/sand/aim-live.png` and `artifacts/sand/aim-summary.png`. Stdout contains `RASTER aim-live` and `RASTER aim-summary`. The live hud contains `pt/s`. The summary hud contains `avg`.
- **Proof.** The live PNG shows the sample dots and an arrow on the groove. The summary PNG shows the stroke after release with the average readout. The control on those shots reads `Aim ON`.

## Gotchas

- The overlay angle is the raw stroke on screen. The throw log still uses the pan-end velocity. They can disagree. That split is in `UX_QUESTIONS.md`.
- The summary clears after 2 seconds. The shot captures it before that timer fires. Unmounting the screen cancels the timer. Leaving the timer pending fails the test's invariant check.
- Whether the white `Aim ON` state is clear on a phone is open. The test only sees the label.
