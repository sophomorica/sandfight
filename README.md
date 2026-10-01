# Sandfight

Two phones, one pile of sand. Flick toward the other phone. Empty your pile to bury them.

This is the iOS prototype. It runs on iPhone 12 and newer. There is no TestFlight build and no App Store submit.

Bundle id: `com.narrowroad.sandfight`.

## One sim, silent opponent

```bash
flutter pub get
flutter run --dart-define=FAKE_UWB=true
```

You are P1. P2 stands at (+0.8, 0) and does not throw back. Flick up the screen. A full flick throws 12. Misses crawl back in about 0.8s. The top bar is their mass, the timer, then your mass.

## Two sims on one Mac

`FAKE_UWB` uses fixed poses and a loopback socket on `127.0.0.1:47631`. The iOS simulator uses the Mac's localhost, so both sims must run on the same Mac. This socket is not used on a phone.

Boot two simulators, then:

```bash
flutter devices
flutter run -d <host-sim> --dart-define=FAKE_UWB=true --dart-define=ROLE=host
flutter run -d <guest-sim> --dart-define=FAKE_UWB=true --dart-define=ROLE=guest
```

Start the host first. Each sim shows Searching until the guest connects. Flick up on both. The host faces +X. The guest faces the host, so up the screen is toward them too.

## Two iPhones

Use a Mac, a USB cable or wireless debugging, and an Apple development team on the Runner target. Open `ios/Runner.xcworkspace` once if Xcode asks you to sign the app. Do not archive it and do not upload it.

```bash
flutter devices
flutter run -d <patrick-iphone>
flutter run -d <other-iphone>
```

Both phones need Bluetooth on. Do not pass `FAKE_UWB`. Tap **Find nearby players** on both. The phone that tapped first waits. The other phone taps the P1 row. The nearest phone is listed first.

Phones in this build aim with the on-screen edge glow. Flick within about 25° of that glow. UWB heading is not wired yet, so a phone without a ranging session can still play.

iPhone 11 and older stop on a screen that asks for an iPhone 12 or newer. Apple does not publish an A14-only device capability, so the check reads the hardware id at launch.

## Build 3

`pubspec.yaml` is `1.0.0+3`. Put `SENTRY_DSN=...` in a gitignored `.env` at the repo root, then run:

```bash
scripts/build_ios_release.sh
```

The script passes `APP_RELEASE=sandfight@<pubspec version>` and does not set `FAKE_UWB`. If `SENTRY_DSN` is missing it warns and still builds. That build sends nothing.

## Sand in a match

The bed is a heightfield. Each raw pointer sample carves it. A fragment shader lights the field with a low upper-left sun, soft shadow, grain, and ambient occlusion. The picture redraws when the sand changes.

The throw that moves mass is still the pan-end velocity. The carve and the throw can disagree. That split is listed in `UX_QUESTIONS.md` under Needs Patrick. Rake, Smooth, and Reset are not in the match.

`shaders/sand.frag` is declared under `flutter: shaders` in `pubspec.yaml`.

## Tests

```bash
flutter analyze
flutter test
```

`test/sand_bed_test.dart` locks the zen hash, the upward carve at 30°, 0°, and −30°, and the fast-flick depth. `test/sand_shot_test.dart` writes match screenshots to `artifacts/sand/`. Those shots are the software raster, not a phone GPU.

The suite covers a flick toward the guest, a miss that returns, truck hit and miss, a dead link that pauses and then ends, fallback aim when UWB is absent, heading that turns with the phone, and the haptic cues. Haptic cues are data on the match. On an iPhone they play through `UIImpactFeedbackGenerator`. A fuller pile is a harder pulse. A loss is three pulses that get softer. The simulator does not have that generator, so a sim falls back to Flutter's coarser taps.

## Pinned choices

Guest heading in the fake match is π, so both players flick up.

One truck exists. It appears for P1 at 20s. If it is still unused 25s later, it moves to P2.

The match clock freezes while the game says "Get closer."

If the 15s overtime ends with no transfer, the result is a draw.

At 90s, sand still in the air is settled, then the phone holding more sand loses.

`bluetooth_low_energy` is the BLE plugin because `flutter_blue_plus` cannot advertise.

On a phone, heading rate is the gyroscope's long-axis reading while the phone is upright.
