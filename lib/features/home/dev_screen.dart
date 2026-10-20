import 'package:flutter/material.dart';

import '../../telemetry/device_log.dart';
import '../../theme/palette.dart';

class DevScreen extends StatefulWidget {
  const DevScreen({super.key});

  @override
  State<DevScreen> createState() => _DevScreenState();
}

class _DevScreenState extends State<DevScreen> {
  DeviceSnapshot _snap = DeviceSnapshot.empty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await DeviceLog.instance.open();
    if (!mounted) return;
    setState(() => _snap = DeviceLog.instance.current);
  }

  @override
  Widget build(BuildContext context) {
    final faults = _snap.faults.reversed.toList();
    return Scaffold(
      backgroundColor: Palette.pit,
      appBar: AppBar(
        backgroundColor: Palette.pit,
        foregroundColor: Palette.ink,
        title: const Text('Device log'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          _Stat('Sessions', _snap.sessions, const Key('stat-sessions')),
          _Stat('Rounds started', _snap.roundsStarted, const Key('stat-rounds-started')),
          _Stat('Rounds finished', _snap.roundsFinished, const Key('stat-rounds-finished')),
          _Stat('Inputs', _snap.inputs, const Key('stat-inputs')),
          _Stat('Throws', _snap.throwsMade, const Key('stat-throws')),
          const SizedBox(height: 20),
          const Text('Recent errors', style: TextStyle(color: Palette.dust, fontSize: 14)),
          const SizedBox(height: 8),
          if (faults.isEmpty)
            const Text('No errors yet.', style: TextStyle(color: Palette.ink, fontSize: 16))
          else
            for (final fault in faults)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(fault.error, style: const TextStyle(color: Palette.ink, fontSize: 14, height: 1.3)),
              ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.valueKey);

  final String label;
  final int value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Palette.beige, fontSize: 18))),
          Text('$value', key: valueKey, style: const TextStyle(color: Palette.ink, fontSize: 22, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
