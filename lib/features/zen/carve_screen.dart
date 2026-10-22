import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import 'sand_stage.dart';

class CarveScreen extends StatefulWidget {
  const CarveScreen({super.key, required this.onLeave});

  final VoidCallback onLeave;

  @override
  State<CarveScreen> createState() => _CarveScreenState();
}

class _CarveScreenState extends State<CarveScreen> {
  final _stage = GlobalKey<SandStageState>();
  var _rake = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.pit,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: widget.onLeave,
                child: const Text(
                  'Leave',
                  style: TextStyle(color: Palette.dust, fontSize: 16),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  key: const ValueKey('garden-rake'),
                  onPressed: () {
                    final next = !_rake;
                    setState(() => _rake = next);
                    _stage.currentState?.setRake(next);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Palette.ink,
                    backgroundColor: _rake ? Palette.rust : null,
                  ),
                  child: const Text(
                    'Rake',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                TextButton(
                  key: const ValueKey('garden-smooth'),
                  onPressed: () => _stage.currentState?.smooth(),
                  child: const Text(
                    'Smooth',
                    style: TextStyle(color: Palette.dust, fontSize: 16),
                  ),
                ),
                TextButton(
                  key: const ValueKey('garden-reset'),
                  onPressed: () => _stage.currentState?.resetGarden(),
                  child: const Text(
                    'Reset',
                    style: TextStyle(color: Palette.dust, fontSize: 16),
                  ),
                ),
              ],
            ),
            Expanded(child: SandStage(key: _stage)),
          ],
        ),
      ),
    );
  }
}
