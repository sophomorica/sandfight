import 'package:flutter/material.dart';

import '../../game/rules.dart';
import '../../game/throw_ray.dart';
import '../../game/truck.dart';
import '../../haptic_player.dart';
import '../../render/sand_field.dart';
import '../../render/truck_sprite.dart';
import '../../theme/palette.dart';

class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key, required this.match, required this.seat, required this.onSwipe, required this.onTruck, required this.onLeave});

  final Match match;
  final Seat seat;
  final void Function(Vec2 origin, Vec2 local, double speed) onSwipe;
  final void Function(Vec2 local) onTruck;
  final VoidCallback onLeave;

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _impact = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  int _seenImpact = 0;
  int _played = 0;
  Offset _drag = Offset.zero;

  @override
  void initState() {
    super.initState();
    _played = widget.match.haptics.length;
    _seenImpact = widget.match.impactGen;
  }

  @override
  void didUpdateWidget(covariant MatchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final match = widget.match;
    if (match.impactSeat == widget.seat && match.impactGen != _seenImpact) {
      _seenImpact = match.impactGen;
      _impact.forward(from: 0);
    }
    for (var i = _played; i < match.haptics.length; i++) {
      final event = match.haptics[i];
      if (event.seat == widget.seat) HapticPlayer.play(event);
    }
    _played = match.haptics.length;
  }

  @override
  void dispose() {
    _impact.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final seat = widget.seat;
    final mine = match.massOf(seat);
    final theirs = match.massOf(otherSeat(seat));
    final me = match.poseFor(seat);
    final them = match.poseFor(otherSeat(seat));
    final aim = screenDirection(them.xy - me.xy, me.hdg);
    final truckHere = match.truck.on && match.truck.owner == seat && match.truck.phase != TruckPhase.none;

    return Scaffold(
      backgroundColor: Palette.pit,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Text('$theirs', key: const Key('their-mass'), style: _mass),
                  const Spacer(),
                  Text(_clock(match.remainingMs), style: const TextStyle(color: Palette.dust, fontSize: 16)),
                  const Spacer(),
                  Text('$mine', key: const Key('my-mass'), style: _mass),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    onPanStart: (_) => _drag = Offset.zero,
                    onPanUpdate: (details) => _drag += details.delta,
                    onPanEnd: (details) {
                      final velocity = details.velocity.pixelsPerSecond;
                      final sample = velocity.distance > 40 ? velocity : _drag;
                      if (sample.distance < 8) return;
                      final speed = (sample.distance / 2000).clamp(0.0, 1.0);
                      widget.onSwipe(const Vec2(0.5, 0.92), Vec2(sample.dx, -sample.dy), speed);
                    },
                    child: AnimatedBuilder(
                      animation: _impact,
                      builder: (context, _) {
                        final pulse = _impact.status == AnimationStatus.dismissed ? 0.0 : 1 - _impact.value;
                        return SandField(
                          grid: match.gridFor(seat),
                          pour: match.pourOf(seat),
                          impact: pulse,
                          clockMs: DateTime.now().millisecondsSinceEpoch,
                        );
                      },
                    ),
                  ),
                  _Glow(dir: aim),
                  if (truckHere)
                    Positioned(
                      left: 24,
                      bottom: 28,
                      child: GestureDetector(
                        onPanEnd: (details) {
                          final velocity = details.velocity.pixelsPerSecond;
                          if (velocity.distance < 8) return;
                          widget.onTruck(Vec2(velocity.dx, -velocity.dy));
                        },
                        child: const TruckSprite(),
                      ),
                    ),
                  if (match.banner != null)
                    Center(
                      child: Text(match.banner!, style: const TextStyle(color: Palette.ink, fontSize: 28, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _mass = TextStyle(color: Palette.ink, fontSize: 22, fontWeight: FontWeight.w700);

String _clock(int ms) {
  final seconds = (ms / 1000).ceil();
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

class _Glow extends StatelessWidget {
  const _Glow({required this.dir});

  final Vec2 dir;

  @override
  Widget build(BuildContext context) {
    final vertical = dir.y.abs() >= dir.x.abs();
    final begin = vertical
        ? (dir.y >= 0 ? Alignment.topCenter : Alignment.bottomCenter)
        : (dir.x >= 0 ? Alignment.centerRight : Alignment.centerLeft);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: begin,
            end: Alignment.center,
            colors: [Palette.glow.withValues(alpha: 0.45), const Color(0x00000000)],
          ),
        ),
      ),
    );
  }
}
