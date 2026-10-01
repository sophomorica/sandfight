# UX questions log

A running log of every UI/UX choice Patrick questions, in the Zen prototype versions or in the current Sand Fight build (including anything in Sand Fight he says he doesn't understand).

Log started **2026-09-25**. The first entry to track: **"Sand Fight sand looks silly / not real sand."**

| # | Date | Source | What he questioned | Status | Resolution / how Zen v1 addresses it |
|---|---|---|---|---|---|
| 1 | 2026-09-25 | Sand Fight | Sand looks silly, not like real sand. | open | Zen v1 is a heightfield carved by the finger, lit by a low 30° upper-left sun with soft shadows, grain, and no outlines. This branch ports that look into the match. The pile numbers are unchanged. Patrick has not looked at it on a phone. |
| 2 | 2026-09-25 | Sand Fight | The swipe must be vector-aware (angle, speed, path), not a canned animation. | open | The match carves each raw pointer sample. The old fixed column of 16 dots is gone. Speed still shallows and widens the groove. The throw that moves mass is still the old velocity vector. See Needs Patrick. |
| 3 | 2026-09-25 | Sand Fight | Precision and responsiveness: no lag, no smoothing drift. | open | Each sample is carved in the pointer handler and joined in a straight line to the previous sample. There is no position smoothing. The lit texture uploads on the next frame. |
| 4 | 2026-09-25 | Sand Fight | Assume portrait, with swipes generally upward. | open | iOS stays portrait-only. The carve follows an upward stroke at any angle, including 30°, 0°, and −30°. |
| 5 | 2026-09-25 | Sand Fight | Visible vector feedback overlay (direction, angle in degrees, speed). | open | An Aim control sits on the match, off by default. On, it draws the raw samples, an arrow from the last 80 ms, the angle (0° = up, clockwise positive), speed, length, and sample count. After release it holds the average for 2 seconds. |
| 6 | 2026-09-25 | Sand Fight | Sand Fight's aim feedback on/off state was unclear. | open | The control turns solid white, dark text, a white ring, and the label **Aim ON**. A pill reads "AIM ON" and "drag to measure" while it is on and idle. Needs Patrick's eyes on a real phone. |
| 7 | 2026-09-25 | Sand Fight | Sand Fight's sand animation looked generic. | open | The match has no pour dots and no scripted grain animation. Marks come from the stroke. Rake, Smooth, and Reset are not in the match. |

## Needs Patrick

These are not decided in this branch. The code takes the conservative side and leaves the call to him.

- Do Rake, Smooth, and Reset belong in a match, or only somewhere else, such as the lobby or a practice garden? This branch does not put them in the match. Finger carve only.
- Is the Aim overlay for players, or a debug toggle? It is in the match, off by default, with a white **Aim ON** state. That does not decide who it is for.
- Is the Aim on/off state clear on a real phone? Entry #6 needs his eyes. The widget test only checks the label and the idle pill.
- Should the throw switch to the full-gesture vector? That is build-4 item 1, and it changes gameplay. The carve follows the raw pointer path. The throw still uses the pan-end velocity, or the drag if that velocity is 40 px/s or less. `assessThrow` is unchanged. Who receives the sand is unchanged.

Also flagged, not guessed:

- The picture of the sand is not the pile. `SandGrid` still holds the mass, and the top numbers still move. The garden does not rise or fall with the pile. Sand that arrives no longer shows falling dots. There is no mound for a received throw.
- The heightfield stays at the prototype scale, 1.25, capped at 700,000 cells. It was not shrunk. On a 390×700 pt bed that is about 488×875 cells. A bench on this machine carved a stroke in well under a frame. The encode of the height texture is the larger CPU cost, about 10 ms here. That number is not a phone frame time.
- The last-stroke readout clears after 2 seconds with no fade. The prototype fades the last 500 ms.
- The grain pattern uses a fixed seed, 11, so the bed does not reshuffle every match.
