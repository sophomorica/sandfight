import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceFault {
  const DeviceFault({required this.atMs, required this.error});

  final int atMs;
  final String error;
}

class DeviceSnapshot {
  const DeviceSnapshot({
    required this.sessions,
    required this.roundsStarted,
    required this.roundsFinished,
    required this.inputs,
    required this.throwsMade,
    required this.faults,
  });

  final int sessions;
  final int roundsStarted;
  final int roundsFinished;
  final int inputs;
  final int throwsMade;
  final List<DeviceFault> faults;

  static const empty = DeviceSnapshot(
    sessions: 0,
    roundsStarted: 0,
    roundsFinished: 0,
    inputs: 0,
    throwsMade: 0,
    faults: [],
  );
}

class DeviceLog {
  DeviceLog._();

  static final instance = DeviceLog._();
  static const _key = 'deviceLog';
  static const _faultCap = 8;

  Future<void>? _opening;
  DeviceSnapshot _memory = DeviceSnapshot.empty;

  DeviceSnapshot get current => _memory;

  @visibleForTesting
  void debugClear() {
    _opening = null;
    _memory = DeviceSnapshot.empty;
  }

  Future<void> open() {
    return _opening ??= _read();
  }

  Future<void> session() => _bump((snap) => snap.sessions += 1);

  Future<void> roundStarted() => _bump((snap) => snap.roundsStarted += 1);

  Future<void> roundFinished() => _bump((snap) => snap.roundsFinished += 1);

  Future<void> input() => _bump((snap) => snap.inputs += 1);

  Future<void> threw() => _bump((snap) => snap.throwsMade += 1);

  Future<void> fault(Object error, StackTrace? stack) => _bump((snap) {
    final next = List<DeviceFault>.of(snap.faults);
    next.add(DeviceFault(atMs: DateTime.now().millisecondsSinceEpoch, error: _faultText(error, stack)));
    if (next.length > _faultCap) next.removeRange(0, next.length - _faultCap);
    snap.faults
      ..clear()
      ..addAll(next);
  });

  Future<void> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      _memory = _decode(raw);
    } catch (_) {
      _memory = DeviceSnapshot.empty;
    }
  }

  Future<void> _bump(void Function(_MutableLog log) change) async {
    try {
      await open();
      final log = _MutableLog.from(_memory);
      change(log);
      _memory = log.snapshot();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, _encode(_memory));
    } catch (_) {}
  }
}

class _MutableLog {
  _MutableLog.from(DeviceSnapshot snap)
    : sessions = snap.sessions,
      roundsStarted = snap.roundsStarted,
      roundsFinished = snap.roundsFinished,
      inputs = snap.inputs,
      throwsMade = snap.throwsMade,
      faults = List<DeviceFault>.of(snap.faults);

  int sessions;
  int roundsStarted;
  int roundsFinished;
  int inputs;
  int throwsMade;
  final List<DeviceFault> faults;

  DeviceSnapshot snapshot() {
    return DeviceSnapshot(
      sessions: sessions,
      roundsStarted: roundsStarted,
      roundsFinished: roundsFinished,
      inputs: inputs,
      throwsMade: throwsMade,
      faults: List<DeviceFault>.unmodifiable(faults),
    );
  }
}

String _faultText(Object error, StackTrace? stack) {
  final head = error.toString().replaceAll('\n', ' ');
  final rows = stack?.toString().split('\n') ?? const <String>[];
  final line = rows.firstWhere((row) => row.trim().isNotEmpty, orElse: () => '');
  final text = line.isEmpty ? head : '$head $line';
  if (text.length <= 180) return text;
  return text.substring(0, 180);
}

String _encode(DeviceSnapshot snap) {
  return jsonEncode({
    'sessions': snap.sessions,
    'roundsStarted': snap.roundsStarted,
    'roundsFinished': snap.roundsFinished,
    'inputs': snap.inputs,
    'throwsMade': snap.throwsMade,
    'faults': [
      for (final fault in snap.faults) {'atMs': fault.atMs, 'error': fault.error},
    ],
  });
}

DeviceSnapshot _decode(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) return DeviceSnapshot.empty;
  final faults = <DeviceFault>[];
  final rows = decoded['faults'];
  if (rows is List) {
    for (final row in rows) {
      if (row is! Map) continue;
      final at = row['atMs'];
      final error = row['error'];
      if (at is! int || error is! String) continue;
      faults.add(DeviceFault(atMs: at, error: error));
    }
  }
  int count(Object? value) => value is int ? value : 0;
  return DeviceSnapshot(
    sessions: count(decoded['sessions']),
    roundsStarted: count(decoded['roundsStarted']),
    roundsFinished: count(decoded['roundsFinished']),
    inputs: count(decoded['inputs']),
    throwsMade: count(decoded['throwsMade']),
    faults: List<DeviceFault>.unmodifiable(faults),
  );
}
