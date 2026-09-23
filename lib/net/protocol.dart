import 'dart:typed_data';

import '../game/haptics.dart';
import '../game/rules.dart';
import '../game/throw_ray.dart';
import '../game/truck.dart';

sealed class Intent {}

class PoseIntent extends Intent {
  PoseIntent(this.seat, this.pose, this.uwb);

  final Seat seat;
  final Pose pose;
  final bool uwb;
}

class SwipeIntent extends Intent {
  SwipeIntent(this.seat, this.origin, this.local, this.speed);

  final Seat seat;
  final Vec2 origin;
  final Vec2 local;
  final double speed;
}

class TruckIntent extends Intent {
  TruckIntent(this.seat, this.local);

  final Seat seat;
  final Vec2 local;
}

class RematchIntent extends Intent {}

class _Writer {
  final _bytes = BytesBuilder();

  void u8(int value) => _bytes.addByte(value & 0xff);

  void u16(int value) {
    final data = ByteData(2)..setUint16(0, value);
    _bytes.add(data.buffer.asUint8List());
  }

  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value);
    _bytes.add(data.buffer.asUint8List());
  }

  void f32(double value) {
    final data = ByteData(4)..setFloat32(0, value);
    _bytes.add(data.buffer.asUint8List());
  }

  Uint8List done() => _bytes.toBytes();
}

class _Reader {
  _Reader(this.bytes);

  final Uint8List bytes;
  int offset = 0;

  int u8() => bytes[offset++];

  int u16() {
    final value = ByteData.sublistView(bytes, offset, offset + 2).getUint16(0);
    offset += 2;
    return value;
  }

  int u32() {
    final value = ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);
    offset += 4;
    return value;
  }

  double f32() {
    final value = ByteData.sublistView(bytes, offset, offset + 4).getFloat32(0);
    offset += 4;
    return value;
  }
}

int _seatCode(Seat? seat) => switch (seat) {
  null => 0,
  Seat.a => 1,
  Seat.b => 2,
};

Seat? _seat(int code) => switch (code) {
  1 => Seat.a,
  2 => Seat.b,
  _ => null,
};

void _writeGrid(_Writer writer, List<int> cells) {
  for (var i = 0; i < cells.length; i += 2) {
    writer.u8((cells[i] << 4) | cells[i + 1]);
  }
}

List<int> _readGrid(_Reader reader) {
  final cells = List<int>.filled(240, 0);
  for (var i = 0; i < cells.length; i += 2) {
    final byte = reader.u8();
    cells[i] = byte >> 4;
    cells[i + 1] = byte & 0x0f;
  }
  return cells;
}

Uint8List encodeSnapshot(Match match, List<HapticEvent> haptics) {
  final writer = _Writer()
    ..u8(0x53)
    ..u8(1)
    ..u32(match.seq)
    ..u32(match.tMs)
    ..u16(match.massOf(Seat.a))
    ..u16(match.massOf(Seat.b));
  _writeGrid(writer, match.gridA.cells);
  _writeGrid(writer, match.gridB.cells);
  writer
    ..u8(match.truck.on ? 1 : 0)
    ..u8(_seatCode(match.truck.owner))
    ..f32(match.poseFor(match.truck.owner ?? Seat.a).xy.x)
    ..f32(match.poseFor(match.truck.owner ?? Seat.a).xy.y)
    ..f32(match.truck.dir.x)
    ..u8(match.truck.stateCode)
    ..f32(match.poseA.xy.x)
    ..f32(match.poseA.xy.y)
    ..f32(match.poseA.hdg)
    ..f32(match.poseB.xy.x)
    ..f32(match.poseB.xy.y)
    ..f32(match.poseB.hdg)
    ..u8(_seatCode(match.winner))
    ..u8(match.phase.index)
    ..u8(match.aim.index)
    ..u8(match.endReason.index)
    ..u32(match.overtimeAt)
    ..u16(match.pourOf(Seat.a))
    ..u16(match.pourOf(Seat.b))
    ..u16(match.impactGen)
    ..u8(_seatCode(match.impactSeat))
    ..u16(match.truck.cargo)
    ..f32(match.truck.dir.y)
    ..u8(haptics.length.clamp(0, 16));
  for (final event in haptics.take(16)) {
    writer
      ..u8(event.kind.index)
      ..u8(_seatCode(event.seat))
      ..u16((event.intensity * 1000).round().clamp(0, 1000));
  }
  return writer.done();
}

SnapshotView? decodeSnapshot(Uint8List bytes) {
  if (bytes.length < 16 || bytes[0] != 0x53) return null;
  final reader = _Reader(bytes)..offset = 2;
  final seq = reader.u32();
  final tMs = reader.u32();
  reader
    ..u16()
    ..u16();
  final gridA = _readGrid(reader);
  final gridB = _readGrid(reader);
  reader.u8();
  final truckOwner = _seat(reader.u8());
  reader
    ..f32()
    ..f32();
  final truckDirX = reader.f32();
  final truckPhase = TruckPhase.values[reader.u8().clamp(0, TruckPhase.values.length - 1)];
  final poseA = Pose(Vec2(reader.f32(), reader.f32()), reader.f32());
  final poseB = Pose(Vec2(reader.f32(), reader.f32()), reader.f32());
  final winner = _seat(reader.u8());
  final phase = Phase.values[reader.u8().clamp(0, Phase.values.length - 1)];
  final aim = AimMode.values[reader.u8().clamp(0, AimMode.values.length - 1)];
  final end = EndReason.values[reader.u8().clamp(0, EndReason.values.length - 1)];
  final overtimeAt = reader.u32();
  final pourA = reader.u16();
  final pourB = reader.u16();
  final impactGen = reader.u16();
  final impactSeat = _seat(reader.u8());
  final cargo = reader.u16();
  final truckDirY = reader.f32();
  final count = reader.u8();
  final haptics = <HapticEvent>[];
  for (var i = 0; i < count; i++) {
    final kind = HapticKind.values[reader.u8().clamp(0, HapticKind.values.length - 1)];
    final seat = _seat(reader.u8()) ?? Seat.a;
    final intensity = reader.u16() / 1000;
    haptics.add(HapticEvent(kind, seat, intensity));
  }
  return SnapshotView(
    seq: seq,
    tMs: tMs,
    gridA: gridA,
    gridB: gridB,
    poseA: poseA,
    poseB: poseB,
    aim: aim,
    phase: phase,
    endReason: end,
    winner: winner,
    impactGen: impactGen,
    impactSeat: impactSeat,
    overtimeAt: overtimeAt,
    truckPhase: truckPhase,
    truckOwner: truckOwner,
    truckCargo: cargo,
    truckDir: Vec2(truckDirX, truckDirY),
    pourA: pourA,
    pourB: pourB,
    haptics: haptics,
  );
}

Uint8List encodeIntent(Intent intent) {
  final writer = _Writer()
    ..u8(0x49)
    ..u8(1);
  switch (intent) {
    case PoseIntent(:final seat, :final pose, :final uwb):
      writer
        ..u8(1)
        ..u8(_seatCode(seat))
        ..f32(pose.xy.x)
        ..f32(pose.xy.y)
        ..f32(pose.hdg)
        ..u8(uwb ? 1 : 0);
    case SwipeIntent(:final seat, :final origin, :final local, :final speed):
      writer
        ..u8(2)
        ..u8(_seatCode(seat))
        ..f32(origin.x)
        ..f32(origin.y)
        ..f32(local.x)
        ..f32(local.y)
        ..f32(speed);
    case TruckIntent(:final seat, :final local):
      writer
        ..u8(3)
        ..u8(_seatCode(seat))
        ..f32(local.x)
        ..f32(local.y);
    case RematchIntent():
      writer
        ..u8(4)
        ..u8(0);
  }
  return writer.done();
}

Intent? decodeIntent(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0x49) return null;
  final reader = _Reader(bytes)..offset = 2;
  final type = reader.u8();
  final seat = _seat(reader.u8()) ?? Seat.b;
  switch (type) {
    case 1:
      return PoseIntent(seat, Pose(Vec2(reader.f32(), reader.f32()), reader.f32()), reader.u8() == 1);
    case 2:
      return SwipeIntent(
        seat,
        Vec2(reader.f32(), reader.f32()),
        Vec2(reader.f32(), reader.f32()),
        reader.f32(),
      );
    case 3:
      return TruckIntent(seat, Vec2(reader.f32(), reader.f32()));
    case 4:
      return RematchIntent();
    default:
      return null;
  }
}
