# Home

Home is the lobby. It names the game, tells you to flick toward the other phone, and offers one way into a match. Phones older than the iPhone 12 stop before this screen.

## Sub-features

- `home-copy` shows the title, the three how-to lines, and `Find nearby players`.
- `home-floor` refuses an iPhone 11 and lets an iPhone 12 through.
- `home-last` shows the last bury when one is stored.

## How to get to it (user POV)

- Launch the app on an iPhone 12 or newer.
- Read the lobby. Tap `Find nearby players` to search.

## Driving it with flutter test

Preconditions:

- `flutter analyze` is clean.
- Shared preferences are mocked. The test does that itself.

- **Lobby.** Run `flutter test test/widget_test.dart --reporter expanded`. The test `home shows find nearby and the last bury` passes. It finds `Find nearby players`, `Hold the phone up.`, `Flick sand toward the other phone.`, `Empty your pile to bury them.`, and `Last bury: P2`.
- **Floor.** The test `iPhone 11 is refused and iPhone 12 reaches home` passes. Machine `iPhone12,1` shows `Sandfight needs an iPhone 12 or newer.` Machine `iPhone13,2` shows `Find nearby players`.
- **Proof.** The transcript is the proof. There is no home screenshot in `artifacts/sand/`.

## Gotchas

- `iPhone12,1` is the iPhone 11. The string looks like a 12. The floor test is the check, not the name.
- Search, the truck, and a real Bluetooth match are not this feature. The lobby button is the entry this file drives.
- A phone launch with `flutter run` is unreachable in an environment with no iPhone. Say so. Do not claim the lobby was seen on a device.
