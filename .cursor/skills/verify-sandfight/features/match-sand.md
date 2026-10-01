# Match sand

The match bed is sand the finger carves. An upward stroke leaves a groove along that stroke, lit by a low upper-left sun. The groove gets shallower when the stroke is fast.

## Sub-features

- `sand-up-30` carves an upward stroke 30° clockwise from up.
- `sand-up-0` carves straight up.
- `sand-up-minus-30` carves 30° the other way.
- `sand-fast` carves the same straight path as a fast flick and leaves a shallower groove.
- `sand-bench` reports carve and encode time on a phone-sized bed.

## How to get to it (user POV)

- Open a match and drag upward on the sand.
- There is no Rake, Smooth, or Reset control on this screen.

## Driving it with flutter test

Preconditions:

- `flutter analyze` is clean.
- No other `flutter test` is using this checkout.

- **Angles and flick.** Run `flutter test test/sand_shot_test.dart --reporter expanded`. The test exits 0. Stdout contains `RASTER up-30`, `RASTER up-0`, `RASTER up-minus-30`, and `RASTER fast-flick`.
- **Files.** The same run writes `artifacts/sand/up-30.png`, `up-0.png`, `up-minus-30.png`, and `fast-flick.png`. Each PNG is a portrait match screen with one groove, the pile numbers, and an Aim control that reads `Aim`.
- **Geometry.** Run `flutter test test/sand_bed_test.dart --reporter expanded`. The upward-stroke test passes. The fast-flick test passes. Stdout contains one `BENCH` line. `worst` on that line is under 16 ms.
- **Proof.** Keep the PNGs and the transcript. The straight-up groove is darker in a band along the stroke than the sand well to its side.

## Gotchas

- The dark core is a few pixels off the sample line because one wall faces the sun. A single center pixel can land on the bright lip.
- `RASTER` milliseconds are the software raster of a 393×852 shader frame. They are not a phone GPU time. The `BENCH` line is the CPU carve and the height encode.
- A fresh bed already differs from flat `#CDB28C`. Waiting until the first non-flat frame does not prove the stroke has uploaded. The shot test captures after the pointer is released and the next frame is pumped.
- The picture of the sand is not the pile. A green shot test does not prove mass moved. Use the throw feature for that.
