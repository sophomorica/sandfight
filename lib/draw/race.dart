import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'stroke.dart';

export 'stroke.dart';

part 'fold.dart';
part 'recognize.dart';
part 'wire.dart';

typedef RaceNow = int Function();

enum Glyph {
  circle(1),
  square(2),
  triangle(3);

  const Glyph(this.id);

  final int id;

  static Glyph? byId(int id) {
    for (final glyph in values) {
      if (glyph.id == id) return glyph;
    }
    return null;
  }
}

enum Place { ahead, behind, tied }

sealed class ClockFace {
  const ClockFace();
}

final class Counting extends ClockFace {
  const Counting(this.remainingMs);

  final int remainingMs;
}

final class Locked extends ClockFace {
  const Locked(this.elapsedMs);

  /// Null when the mark is blank.
  final int? elapsedMs;
}

sealed class RaceInput {
  const RaceInput._();
}

final class StrokeUp extends RaceInput {
  const StrokeUp(this.stroke) : super._();

  final Stroke stroke;
}

final class ClockTick extends RaceInput {
  const ClockTick() : super._();
}

abstract interface class RaceSeat {
  Glyph get glyph;

  ClockFace get clock;

  Place? get showing;

  /// Reduces a copy and returns the posted seat. The receiver stays as it was.
  RaceSeat turn(RaceInput input);
}
