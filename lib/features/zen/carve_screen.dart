import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import 'sand_stage.dart';

class CarveScreen extends StatelessWidget {
  const CarveScreen({super.key, required this.onLeave});

  final VoidCallback onLeave;

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
                onPressed: onLeave,
                child: const Text(
                  'Leave',
                  style: TextStyle(color: Palette.dust, fontSize: 16),
                ),
              ),
            ),
            const Expanded(child: SandStage()),
          ],
        ),
      ),
    );
  }
}
