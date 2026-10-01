import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../game/rules.dart';
import '../../game/throw_ray.dart';
import '../../game/truck.dart';
import '../../haptic_player.dart';
import '../../render/aim_overlay.dart';
import '../../render/sand_bed.dart';
import '../../render/sand_field.dart';
import '../../render/truck_sprite.dart';
import '../../telemetry/aim_log.dart';
import '../../theme/palette.dart';

class MatchScreen extends StatefulWidget {
  const MatchScreen({
    super.key,
    required this.match,
    required this.seat,
    required this.onSwipe,
    required this.onTruck,
    required this.onLeave,
    this.onAim,
  });

  final Match match;
  final Seat seat;
  final void Function(Vec2 origin, Vec2 local, double speed) onSwipe;
  final void Function(Vec2 local) onTruck;
  final VoidCallback onLeave;
  final void Function(AimThrow throwAim)? onAim;

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  int _seenImpact = 0;
  int _played = 0;
  Offset _drag = Offset.zero;
  DateTime? _panAt;
  SandBed? _bed;
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  ui.Image? _image;
  int _shownGeneration = -1;
  bool _uploading = false;
  bool _uploadAgain = false;
  bool _aimOn = false;
  AimReadout? _summary;
  Timer? _summaryTimer;
  bool _frameQueued = false;

  @override
  void initState() {
    super.initState();
    _played = widget.match.haptics.length;
    _seenImpact = widget.match.impactGen;
    _loadShader();
  }

  @override
  void didUpdateWidget(covariant MatchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final match = widget.match;
    if (match.impactSeat == widget.seat && match.impactGen != _seenImpact) {
      _seenImpact = match.impactGen;
    }
    for (var i = _played; i < match.haptics.length; i++) {
      final event = match.haptics[i];
      if (event.seat == widget.seat) HapticPlayer.play(event);
    }
    _played = match.haptics.length;
  }

  @override
  void dispose() {
    _summaryTimer?.cancel();
    _image?.dispose();
    _shader?.dispose();
    _program = null;
    super.dispose();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/sand.frag');
      if (!mounted) {
        program.fragmentShader().dispose();
        return;
      }
      setState(() {
        _program = program;
        _shader = program.fragmentShader();
      });
      _upload();
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'sand field'));
    }
  }

  SandBed _ensureBed(double width, double height) {
    final current = _bed;
    if (current != null && (current.widthPt - width).abs() < 1 && (current.heightPt - height).abs() < 1) {
      return current;
    }
    final bed = SandBed.fit(width, height);
    _bed = bed;
    _shownGeneration = -1;
    _image?.dispose();
    _image = null;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_bed, bed)) return;
      _upload();
    });
    return bed;
  }

  void _scheduleFrame() {
    if (_frameQueued) return;
    _frameQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _frameQueued = false;
      if (!mounted) return;
      final bed = _bed;
      if (bed == null) return;
      if (bed.dirty) bed.slump();
      setState(() {});
      _upload();
    });
  }

  Future<void> _upload() async {
    final bed = _bed;
    final shader = _shader;
    if (bed == null || shader == null || _program == null) return;
    if (_shownGeneration == bed.generation && _image != null) return;
    if (_uploading) {
      _uploadAgain = true;
      return;
    }
    _uploading = true;
    final generation = bed.generation;
    try {
      final bytes = bed.encodeHeight();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: bed.cols,
        height: bed.rows,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      buffer.dispose();
      descriptor.dispose();
      codec.dispose();
      if (!mounted || !identical(_bed, bed)) {
        frame.image.dispose();
        return;
      }
      final previous = _image;
      setState(() {
        _image = frame.image;
        _shownGeneration = generation;
      });
      previous?.dispose();
    } finally {
      _uploading = false;
      if (_uploadAgain) {
        _uploadAgain = false;
        _upload();
      }
    }
  }

  void _down(PointerDownEvent event) {
    final bed = _bed;
    if (bed == null) return;
    _summaryTimer?.cancel();
    _summary = null;
    bed.down(event.pointer, event.localPosition.dx, event.localPosition.dy, _ms(event));
    _scheduleFrame();
  }

  void _move(PointerMoveEvent event) {
    final bed = _bed;
    if (bed == null) return;
    bed.move(event.pointer, event.localPosition.dx, event.localPosition.dy, _ms(event));
    _scheduleFrame();
  }

  void _up(PointerUpEvent event) => _endPointer(event.pointer, event.localPosition, _ms(event));

  void _cancel(PointerCancelEvent event) => _endPointer(event.pointer, event.localPosition, _ms(event));

  void _endPointer(int pointer, Offset position, double tMs) {
    final bed = _bed;
    if (bed == null) return;
    bed.up(pointer, position.dx, position.dy, tMs);
    if (_aimOn && bed.samples.length > 1) {
      _summary = summaryAim(bed.samples, peak: bed.peak, length: bed.length);
      _summaryTimer?.cancel();
      _summaryTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() => _summary = null);
      });
    }
    _scheduleFrame();
  }

  double _ms(PointerEvent event) => event.timeStamp.inMicroseconds / 1000.0;

  void _toggleAim() {
    setState(() {
      _aimOn = !_aimOn;
      if (!_aimOn) {
        _summary = null;
        _summaryTimer?.cancel();
      }
    });
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
    final bed = _bed;
    final readout = !_aimOn
        ? null
        : bed != null && bed.stroking
        ? liveAim(bed.samples)
        : (_summary ?? AimReadout.idle);

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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final field = _ensureBed(constraints.maxWidth, constraints.maxHeight);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: _down,
                        onPointerMove: _move,
                        onPointerUp: _up,
                        onPointerCancel: _cancel,
                        child: GestureDetector(
                          onPanStart: (_) {
                            _drag = Offset.zero;
                            _panAt = DateTime.now();
                          },
                          onPanUpdate: (details) => _drag += details.delta,
                          onPanEnd: (details) {
                            final velocity = details.velocity.pixelsPerSecond;
                            final sample = velocity.distance > 40 ? velocity : _drag;
                            if (sample.distance < 8) return;
                            final speed = (sample.distance / 2000).clamp(0.0, 1.0);
                            final local = Vec2(sample.dx, -sample.dy);
                            final started = _panAt;
                            final durationMs = started == null ? 0.0 : DateTime.now().difference(started).inMilliseconds.toDouble();
                            widget.onSwipe(const Vec2(0.5, 0.92), local, speed);
                            final report = widget.onAim;
                            if (report == null) return;
                            final current = widget.match;
                            final who = widget.seat;
                            report(
                              assessThrow(
                                local: local,
                                speed: speed,
                                lengthPx: _drag.distance,
                                durationMs: durationMs,
                                me: current.poseFor(who),
                                them: current.poseFor(otherSeat(who)),
                                aim: current.aim,
                              ),
                            );
                          },
                          child: SandField(image: _image, shader: _shader, generation: field.generation),
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
                          child: Text(
                            match.banner!,
                            style: const TextStyle(color: Palette.ink, fontSize: 28, fontWeight: FontWeight.w700),
                          ),
                        ),
                      if (readout != null) AimOverlay(readout: readout, fade: 1),
                      if (readout != null)
                        Positioned(
                          top: 8,
                          left: 16,
                          right: 16,
                          child: Center(child: _AimHud(readout: readout)),
                        ),
                      Positioned(left: 0, right: 0, bottom: 10, child: Center(child: _AimButton(on: _aimOn, onPressed: _toggleAim))),
                    ],
                  );
                },
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

class _AimHud extends StatelessWidget {
  const _AimHud({required this.readout});

  final AimReadout readout;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: const Color(0xBD160F08), borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: readout.headline,
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
              ),
              TextSpan(
                text: '   ${readout.detail}',
                style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          key: const Key('aim-hud'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _AimButton extends StatelessWidget {
  const _AimButton({required this.on, required this.onPressed});

  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final fg = on ? const Color(0xFF2A1D10) : const Color(0xC7FFF9EE);
    return Semantics(
      button: true,
      toggled: on,
      label: on ? 'Aim ON' : 'Aim',
      child: Material(
        color: on ? const Color(0xFFFFFAF0) : const Color(0x4234281C),
        borderRadius: BorderRadius.circular(18),
        elevation: on ? 3 : 0,
        child: InkWell(
          key: const Key('aim-toggle'),
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Container(
            width: 74,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: on ? Border.all(color: Colors.white, width: 1.5) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.my_location, size: 16, color: fg),
                const SizedBox(height: 2),
                Text(on ? 'Aim ON' : 'Aim', style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
