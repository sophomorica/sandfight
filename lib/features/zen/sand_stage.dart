import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../draw/stroke.dart';
import '../../render/sand_bed.dart';
import '../../render/sand_field.dart';

class SandStage extends StatefulWidget {
  const SandStage({super.key, this.onStroke});

  final void Function(List<DrawPoint> points)? onStroke;

  @override
  State<SandStage> createState() => SandStageState();
}

class SandStageState extends State<SandStage> {
  void setRake(bool value) {
    _bed?.rake = value;
  }

  void smooth() {
    final bed = _bed;
    if (bed == null) return;
    bed.smoothGarden();
    setState(() {});
    _upload();
  }

  void resetGarden() {
    final bed = _bed;
    if (bed == null) return;
    bed.resetGarden();
    setState(() {});
    _upload();
  }

  SandBed? _bed;
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  ui.Image? _image;
  int _shownGeneration = -1;
  bool _uploading = false;
  bool _uploadAgain = false;
  bool _frameQueued = false;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  @override
  void dispose() {
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
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'sand field',
        ),
      );
    }
  }

  SandBed _ensureBed(double width, double height) {
    final current = _bed;
    if (current != null &&
        (current.widthPt - width).abs() < 1 &&
        (current.heightPt - height).abs() < 1) {
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
    bed.down(
      event.pointer,
      event.localPosition.dx,
      event.localPosition.dy,
      _ms(event),
    );
    _scheduleFrame();
  }

  void _move(PointerMoveEvent event) {
    final bed = _bed;
    if (bed == null) return;
    bed.move(
      event.pointer,
      event.localPosition.dx,
      event.localPosition.dy,
      _ms(event),
    );
    _scheduleFrame();
  }

  void _up(PointerUpEvent event) {
    _end(event.pointer, event.localPosition, _ms(event));
  }

  void _cancel(PointerCancelEvent event) {
    _end(event.pointer, event.localPosition, _ms(event));
  }

  void _end(int pointer, Offset position, double tMs) {
    final bed = _bed;
    if (bed == null) return;
    bed.up(pointer, position.dx, position.dy, tMs);
    _scheduleFrame();
    final report = widget.onStroke;
    if (report == null) return;
    report([for (final sample in bed.samples) DrawPoint(sample.x, sample.y)]);
  }

  double _ms(PointerEvent event) => event.timeStamp.inMicroseconds / 1000.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bed = _ensureBed(constraints.maxWidth, constraints.maxHeight);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _cancel,
          child: SandField(
            image: _image,
            shader: _shader,
            generation: bed.generation,
          ),
        );
      },
    );
  }
}
