import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'sand_look.dart';

class SandField extends StatelessWidget {
  const SandField({super.key, required this.image, required this.shader, required this.generation});

  final ui.Image? image;
  final ui.FragmentShader? shader;
  final int generation;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SandPainter(image: image, shader: shader, generation: generation),
      child: const SizedBox.expand(),
    );
  }
}

class _SandPainter extends CustomPainter {
  _SandPainter({required this.image, required this.shader, required this.generation});

  final ui.Image? image;
  final ui.FragmentShader? shader;
  final int generation;

  @override
  void paint(Canvas canvas, Size size) {
    final image = this.image;
    final shader = this.shader;
    if (image == null || shader == null || size.isEmpty) {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFCDB28C));
      return;
    }
    bindSandShader(shader, image, size);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _SandPainter oldDelegate) => oldDelegate.generation != generation || oldDelegate.image != image;
}

void bindSandShader(ui.FragmentShader shader, ui.Image image, Size size) {
  final el = SandLook.sunElevationDeg * math.pi / 180;
  final az = SandLook.sunAzimuthDeg * math.pi / 180;
  final cosEl = math.cos(el);
  final sinEl = math.sin(el);
  final cosAz = math.cos(az);
  final sinAz = math.sin(az);
  final lx = sinAz * cosEl;
  final ly = -cosAz * cosEl;
  final lz = sinEl;
  var i = 0;
  void f(double value) => shader.setFloat(i++, value);
  f(size.width);
  f(size.height);
  f(1 / image.width);
  f(1 / image.height);
  f(image.width.toDouble());
  f(image.height.toDouble());
  f(lx);
  f(ly);
  f(lz);
  f(SandLook.sunColor[0]);
  f(SandLook.sunColor[1]);
  f(SandLook.sunColor[2]);
  f(SandLook.skyColor[0]);
  f(SandLook.skyColor[1]);
  f(SandLook.skyColor[2]);
  f(SandLook.sandBase[0]);
  f(SandLook.sandBase[1]);
  f(SandLook.sandBase[2]);
  f(SandLook.sandLight[0]);
  f(SandLook.sandLight[1]);
  f(SandLook.sandLight[2]);
  f(SandLook.sandDark[0]);
  f(SandLook.sandDark[1]);
  f(SandLook.sandDark[2]);
  f(sinEl / cosEl);
  f(SandLook.relief);
  f(SandLook.shadowSoft);
  f(SandLook.ao);
  f(SandLook.mottle);
  f(SandLook.depthDarken);
  f(SandLook.vignette);
  f(SandLook.grainAmount);
  f(SandLook.grainSizePt);
  f(SandLook.grainNormal);
  f(SandLook.grainSpecks);
  f(SandLook.glitter);
  f(SandLook.heightMin);
  f(SandLook.heightMax);
  shader.setImageSampler(0, image);
}
