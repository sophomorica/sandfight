import 'dart:math' as math;

abstract final class SandLook {
  static const simScale = 1.25;
  static const maxCells = 700000;
  static const maxDpr = 2.0;

  static const fingerRadius = 7.0;
  static const fingerDepth = 0.55;
  static const fingerProfile = 0.7;

  static const speedSlow = 150.0;
  static const speedFast = 1800.0;
  static const depthLoss = 0.35;
  static const widthGain = 0.25;
  static const aheadBase = 0.25;
  static const aheadGain = 1.4;
  static const spray = 1.0;

  static const ridgeRatio = 0.85;
  static const ridgeInner = 1.12;
  static const ridgeOuter = 2.4;
  static const ridgeCrumble = 0.45;
  static const streaks = 0.14;
  static const edgeWobble = 0.12;
  static const talus = 0.85;
  static const relaxIters = 2;

  static const sunElevationDeg = 30.0;
  static const sunAzimuthDeg = 315.0;
  static const sunColor = [1.16, 1.04, 0.88];
  static const skyColor = [0.44, 0.47, 0.55];
  static const relief = 1.0;
  static const shadowSoft = 0.07;
  static const ao = 0.10;

  static const sandBase = [0xCD / 255.0, 0xB2 / 255.0, 0x8C / 255.0];
  static const sandLight = [0xF2 / 255.0, 0xE7 / 255.0, 0xD2 / 255.0];
  static const sandDark = [0x6B / 255.0, 0x56 / 255.0, 0x41 / 255.0];
  static const mottle = 0.05;
  static const grainAmount = 0.13;
  static const grainSizePt = 0.5;
  static const grainNormal = 0.55;
  static const grainSpecks = 0.07;
  static const glitter = 0.5;
  static const depthDarken = 0.07;
  static const vignette = 0.2;

  static const heightMin = -12.0;
  static const heightMax = 12.0;
}

int sandHashUint(int x, int y) {
  var h = _toInt32(x * 374761393.0 + y * 668265263.0);
  h = _toInt32(_xor32(h, _urshift(h, 13)).toDouble() * 1274126177.0);
  return _xor32(h, _urshift(h, 16)) & 0xFFFFFFFF;
}

double sandHash01(int x, int y) => sandHashUint(x, y) / 4294967295.0;

double sandNoise2(double x, double y) {
  final xi = x.floor();
  final yi = y.floor();
  var fx = x - xi;
  var fy = y - yi;
  fx = fx * fx * (3 - 2 * fx);
  fy = fy * fy * (3 - 2 * fy);
  final a = sandHash01(xi, yi);
  final b = sandHash01(xi + 1, yi);
  final c = sandHash01(xi, yi + 1);
  final d = sandHash01(xi + 1, yi + 1);
  return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy;
}

double sandNoise1(double x) {
  final i = x.floor();
  var f = x - i;
  f = f * f * (3 - 2 * f);
  final a = sandHash01(i, 91);
  final b = sandHash01(i + 1, 91);
  return a + (b - a) * f;
}

double screenAngleDeg(double dx, double dy) => math.atan2(dx, -dy) * 180 / math.pi;

int _toInt32(double value) {
  if (value.isNaN || value.isInfinite) return 0;
  var n = value.truncateToDouble().remainder(4294967296.0);
  if (n < 0) n += 4294967296.0;
  if (n >= 2147483648.0) return (n - 4294967296.0).toInt();
  return n.toInt();
}

int _urshift(int signed32, int n) {
  final u = signed32 < 0 ? signed32 + 0x100000000 : signed32;
  return u >>> n;
}

int _xor32(int a, int b) {
  final x = (a & 0xFFFFFFFF) ^ (b & 0xFFFFFFFF);
  return x >= 0x80000000 ? x - 0x100000000 : x;
}
