import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

import '../telemetry/crash_reporting.dart';
import '../telemetry/game_watch.dart';
import 'pipe.dart';
import 'tcp_pipe.dart';

class NearbyPeer {
  const NearbyPeer({required this.id, required this.rssi});

  final String id;
  final int rssi;
}

class BleSession {
  final _central = CentralManager();
  final _peripheral = PeripheralManager();
  final _peers = <String, Peripheral>{};
  final _rssi = <String, int>{};
  final _subs = <StreamSubscription<dynamic>>[];

  var _role = _Role.open;

  bool get isGuest => _role == _Role.guest;
  var _started = false;

  void Function(List<NearbyPeer> peers)? onPeers;
  void Function(BytePipe pipe)? onReady;
  void Function(String message)? onError;

  static final serviceId = UUID.fromString('6f8c2a10-9b4e-4c1d-8a77-1d2e3f4a5b6c');
  static final intentId = UUID.fromString('6f8c2a11-9b4e-4c1d-8a77-1d2e3f4a5b6c');
  static final snapshotId = UUID.fromString('6f8c2a12-9b4e-4c1d-8a77-1d2e3f4a5b6c');

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _watchState(_central);
    _watchState(_peripheral);
    await _waitUntilReady(_central);
    await _waitUntilReady(_peripheral);
    final intent = GATTCharacteristic.mutable(
      uuid: intentId,
      properties: [GATTCharacteristicProperty.write, GATTCharacteristicProperty.writeWithoutResponse],
      permissions: [GATTCharacteristicPermission.write],
      descriptors: [],
    );
    final snapshot = GATTCharacteristic.mutable(
      uuid: snapshotId,
      properties: [GATTCharacteristicProperty.notify, GATTCharacteristicProperty.read],
      permissions: [GATTCharacteristicPermission.read],
      descriptors: [],
    );
    final service = GATTService(
      uuid: serviceId,
      isPrimary: true,
      includedServices: [],
      characteristics: [intent, snapshot],
    );
    await _peripheral.addService(service);
    await _peripheral.startAdvertising(Advertisement(name: 'Sandfight', serviceUUIDs: [serviceId]));
    _subs.add(
      _peripheral.characteristicWriteRequested.listen((event) async {
        if (event.characteristic.uuid != intentId) return;
        try {
          await _peripheral.respondWriteRequest(event.request);
        } catch (error, stack) {
          unawaited(CrashReportingService.instance.handled(error, stack, GameSignal.sessionError, {'code': 5}));
        }
        if (_role == _Role.guest) return;
        _lockHost(event.central, snapshot).add(event.request.value);
      }),
    );
    _subs.add(
      _peripheral.characteristicNotifyStateChanged.listen((event) {
        if (!event.state || event.characteristic.uuid != snapshotId) return;
        if (_role == _Role.guest) return;
        _lockHost(event.central, snapshot);
      }),
    );
    _subs.add(
      _peripheral.characteristicReadRequested.listen((event) async {
        try {
          await _peripheral.respondReadRequestWithValue(event.request, value: Uint8List(1));
        } catch (error, stack) {
          unawaited(CrashReportingService.instance.handled(error, stack, GameSignal.sessionError, {'code': 8}));
        }
      }),
    );
    _subs.add(
      _central.discovered.listen((event) {
        final services = event.advertisement.serviceUUIDs;
        if (!services.any((id) => id == serviceId)) return;
        final id = event.peripheral.uuid.toString();
        _peers[id] = event.peripheral;
        _rssi[id] = event.rssi;
        _publish();
      }),
    );
    await _central.startDiscovery(serviceUUIDs: [serviceId]);
  }

  Future<void> join(String id) async {
    final peer = _peers[id];
    if (peer == null || _role != _Role.open) return;
    _role = _Role.guest;
    await _central.stopDiscovery();
    try {
      await _peripheral.stopAdvertising();
    } catch (error, stack) {
      unawaited(CrashReportingService.instance.handled(error, stack, GameSignal.sessionError, {'code': 7}));
    }
    await _central.connect(peer);
    final services = await _central.discoverGATT(peer);
    GATTCharacteristic? intent;
    GATTCharacteristic? snapshot;
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == intentId) intent = characteristic;
        if (characteristic.uuid == snapshotId) snapshot = characteristic;
      }
    }
    if (intent == null || snapshot == null) {
      onError?.call('That phone is not hosting Sandfight.');
      unawaited(CrashReportingService.instance.failure(GameSignal.sessionError, {'code': 2}));
      _role = _Role.open;
      return;
    }
    final pipe = _GuestPipe(_central, peer, intent, snapshot);
    await _central.setCharacteristicNotifyState(peer, snapshot, state: true);
    _subs.add(_central.characteristicNotified.listen(pipe.onNotify));
    onReady?.call(pipe);
  }

  Future<void> stop() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    try {
      await _central.stopDiscovery();
    } catch (error, stack) {
      unawaited(CrashReportingService.instance.handled(error, stack, GameSignal.sessionError, {'code': 6}));
    }
    try {
      await _peripheral.stopAdvertising();
    } catch (error, stack) {
      unawaited(CrashReportingService.instance.handled(error, stack, GameSignal.sessionError, {'code': 7}));
    }
  }

  _HostPipe? _hostPipe;

  _HostPipe _lockHost(Central central, GATTCharacteristic snapshot) {
    final existing = _hostPipe;
    if (existing != null) return existing;
    _role = _Role.host;
    final pipe = _HostPipe(_peripheral, central, snapshot);
    _hostPipe = pipe;
    unawaited(_central.stopDiscovery());
    onReady?.call(pipe);
    return pipe;
  }

  void _publish() {
    final rows = _peers.keys.map((id) => NearbyPeer(id: id, rssi: _rssi[id] ?? -100)).toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    onPeers?.call(rows);
  }

  void _watchState(dynamic manager) {
    final state = manager.state as BluetoothLowEnergyState;
    _report(state);
    _subs.add(
      (manager.stateChanged as Stream<BluetoothLowEnergyStateChangedEventArgs>).listen((event) => _report(event.state)),
    );
  }

  void _report(BluetoothLowEnergyState state) {
    switch (state) {
      case BluetoothLowEnergyState.poweredOff:
        onError?.call('Turn Bluetooth on.');
        unawaited(CrashReportingService.instance.failure(GameSignal.permissionDenied, {'state': 4}));
      case BluetoothLowEnergyState.unauthorized:
        onError?.call('Allow Bluetooth for Sandfight.');
        unawaited(CrashReportingService.instance.failure(GameSignal.permissionDenied, {'state': 2}));
      case BluetoothLowEnergyState.unsupported:
        onError?.call('This phone has no Bluetooth.');
        unawaited(CrashReportingService.instance.failure(GameSignal.permissionDenied, {'state': 1}));
      case BluetoothLowEnergyState.unknown:
      case BluetoothLowEnergyState.poweredOn:
        break;
    }
  }

  Future<void> _waitUntilReady(dynamic manager) async {
    if (manager.state == BluetoothLowEnergyState.poweredOn) return;
    await (manager.stateChanged as Stream<BluetoothLowEnergyStateChangedEventArgs>)
        .firstWhere((event) => event.state == BluetoothLowEnergyState.poweredOn)
        .timeout(const Duration(seconds: 12));
  }
}

enum _Role { open, host, guest }

class _HostPipe implements BytePipe {
  _HostPipe(this._peripheral, this._central, this._snapshot);

  final PeripheralManager _peripheral;
  final Central _central;
  final GATTCharacteristic _snapshot;
  final _reader = FrameReader();
  final _in = StreamController<Uint8List>();
  var _chunk = 180;
  Future<void> _tail = Future<void>.value();

  void add(Uint8List chunk) {
    for (final frame in _reader.add(chunk)) {
      _in.add(frame);
    }
  }

  @override
  Stream<Uint8List> get inbound => _in.stream;

  @override
  void send(Uint8List payload) {
    _tail = _tail.then((_) => _notify(payload)).catchError((_) {});
  }

  Future<void> _notify(Uint8List payload) async {
    try {
      final max = await _peripheral.getMaximumNotifyLength(_central);
      if (max >= 20) _chunk = max;
    } catch (error, stack) {
      unawaited(CrashReportingService.instance.handled(error, stack, GameSignal.sessionError, {'code': 9}));
    }
    final framed = framePayload(payload);
    for (var i = 0; i < framed.length; i += _chunk) {
      final end = math.min(i + _chunk, framed.length);
      await _peripheral.notifyCharacteristic(
        _central,
        _snapshot,
        value: Uint8List.sublistView(framed, i, end),
      );
    }
  }

  @override
  Future<void> close() async {
    await _in.close();
  }
}

class _GuestPipe implements BytePipe {
  _GuestPipe(this._central, this._peripheral, this._intent, this._snapshot);

  final CentralManager _central;
  final Peripheral _peripheral;
  final GATTCharacteristic _intent;
  final GATTCharacteristic _snapshot;
  final _reader = FrameReader();
  final _in = StreamController<Uint8List>();
  var _chunk = 180;
  Future<void> _tail = Future<void>.value();

  void onNotify(GATTCharacteristicNotifiedEventArgs event) {
    if (event.characteristic.uuid != _snapshot.uuid) return;
    for (final frame in _reader.add(event.value)) {
      _in.add(frame);
    }
  }

  @override
  Stream<Uint8List> get inbound => _in.stream;

  @override
  void send(Uint8List payload) {
    _tail = _tail.then((_) => _write(payload)).catchError((_) {});
  }

  Future<void> _write(Uint8List payload) async {
    try {
      final max = await _central.getMaximumWriteLength(_peripheral, type: GATTCharacteristicWriteType.withResponse);
      if (max >= 20) _chunk = max;
    } catch (error, stack) {
      unawaited(CrashReportingService.instance.handled(error, stack, GameSignal.sessionError, {'code': 10}));
    }
    final framed = framePayload(payload);
    for (var i = 0; i < framed.length; i += _chunk) {
      final end = math.min(i + _chunk, framed.length);
      await _central.writeCharacteristic(
        _peripheral,
        _intent,
        value: Uint8List.sublistView(framed, i, end),
        type: GATTCharacteristicWriteType.withResponse,
      );
    }
  }

  @override
  Future<void> close() async {
    await _central.disconnect(_peripheral);
    await _in.close();
  }
}
