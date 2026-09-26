# Throw

A flick up the sand throws 12 mass to the other phone when the aim is true. The groove under the finger is not what decides the hit.

## Sub-features

- `throw-hit` moves 12 from my pile to theirs on an upward fling in the local match.
- `throw-log` still reports the throw through the existing aim log. The carve path is not the vector.

## How to get to it (user POV)

- In a match, flick upward toward the glowing edge.
- Read the two pile numbers in the top bar.

## Driving it with flutter test

Preconditions:

- `flutter analyze` is clean.
- `LocalDrive` is the opponent. No second device.

- **Fling.** Run `flutter test test/widget_test.dart --reporter expanded`. The test `a flick up the pile moves 12 mass` passes.
- **Numbers.** After `tester.fling` on `SandField` with `Offset(0, -700)` at speed 5000, `Key('my-mass')` reads `88` and `Key('their-mass')` reads `112`.
- **Rules.** Run `flutter test test/spec_cases_test.dart --reporter expanded`. Hit, miss, truck, link, fallback, heading, haptics, and the timer tests pass.
- **Proof.** The transcript shows those tests passing. A sand PNG is not proof of the throw.

## Gotchas

- Changing the throw to the full-gesture vector is build 4 and changes who can receive the sand. Do not "fix" a disagreement between the groove and the mass move inside this feature.
- The fling uses the gesture velocity. A slow drag under 8 px is ignored. A velocity of 40 px/s or less falls back to the accumulated drag.
- Spec tests lock `throwMass`, the ray, and the 25° fallback cone. A green sand-bed test does not replace them.
