part of 'race.dart';

const _verdict = 0x56;
const _decision = 0x44;
const _version = 1;
const _scoredKind = 1;
const _blankKind = 2;

final class _MarkHeard extends RaceInput {
  const _MarkHeard(this.mark) : super._();

  final _Mark mark;
}

final class _DecisionHeard extends RaceInput {
  const _DecisionHeard(this.decision) : super._();

  final _Decision decision;
}

final class RacePort {
  factory RacePort({
    required void Function(Uint8List bytes) send,
    required Stream<Uint8List> inbound,
  }) {
    return RacePort._(send, inbound);
  }

  RacePort._(this._send, this._inbound);

  final void Function(Uint8List bytes) _send;
  final Stream<Uint8List> _inbound;
  StreamSubscription<Uint8List>? _sub;

  void listen(void Function(RaceInput input) onInput) {
    if (_sub != null) throw StateError('RacePort is already listening');
    _sub = _inbound.listen((bytes) {
      final input = _decode(bytes);
      if (input != null) onInput(input);
    });
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
  }

  void _emit(_Mark? mark, _Decision? decision) {
    if (mark != null) _send(_encodeVerdict(mark));
    if (decision != null) _send(_encodeDecision(decision));
  }
}

Uint8List _encodeVerdict(_Mark mark) {
  final data = ByteData(8)
    ..setUint8(0, _verdict)
    ..setUint8(1, _version)
    ..setUint8(2, mark.glyph.id);
  switch (mark) {
    case _Scored(:final elapsedMs):
      data
        ..setUint8(3, _scoredKind)
        ..setUint32(4, elapsedMs);
    case _Blank():
      data
        ..setUint8(3, _blankKind)
        ..setUint32(4, 0);
  }
  return data.buffer.asUint8List();
}

Uint8List _encodeDecision(_Decision decision) {
  final outcome = switch (decision) {
    _DrawDecision() => 0,
    _WinDecision(:final winner) => winner == _Bench.caller ? 1 : 2,
  };
  final data = ByteData(3)
    ..setUint8(0, _decision)
    ..setUint8(1, _version)
    ..setUint8(2, outcome);
  return data.buffer.asUint8List();
}

RaceInput? _decode(Uint8List bytes) {
  if (bytes.length == 8 && bytes[0] == _verdict) {
    if (bytes[1] != _version) return null;
    final glyph = Glyph.byId(bytes[2]);
    if (glyph == null) return null;
    final elapsed = ByteData.sublistView(bytes, 4, 8).getUint32(0);
    final mark = switch (bytes[3]) {
      _scoredKind => _Scored(glyph, elapsed),
      _blankKind => _Blank(glyph),
      _ => null,
    };
    if (mark == null) return null;
    return _MarkHeard(mark);
  }
  if (bytes.length == 3 && bytes[0] == _decision) {
    if (bytes[1] != _version) return null;
    final decision = switch (bytes[2]) {
      0 => const _DrawDecision(),
      1 => const _WinDecision(_Bench.caller),
      2 => const _WinDecision(_Bench.drawer),
      _ => null,
    };
    if (decision == null) return null;
    return _DecisionHeard(decision);
  }
  return null;
}
