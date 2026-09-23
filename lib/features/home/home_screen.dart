import 'package:flutter/material.dart';

import '../../theme/palette.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onFind, required this.lastWinner});

  final VoidCallback onFind;
  final String? lastWinner;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.pit,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 36, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sandfight',
                style: TextStyle(color: Palette.ink, fontSize: 48, fontWeight: FontWeight.w700, height: 1),
              ),
              const SizedBox(height: 12),
              const Text(
                'Two phones. One pile. Flick toward them.',
                style: TextStyle(color: Palette.beige, fontSize: 18, height: 1.3),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.beige,
                    foregroundColor: Palette.pit,
                    textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  onPressed: onFind,
                  child: const Text('Find nearby players'),
                ),
              ),
              const SizedBox(height: 28),
              const Text('How to play', style: TextStyle(color: Palette.dust, fontSize: 14)),
              const SizedBox(height: 8),
              const Text('Hold the phone up.', style: TextStyle(color: Palette.ink, fontSize: 16, height: 1.4)),
              const Text(
                'Flick sand toward the other phone.',
                style: TextStyle(color: Palette.ink, fontSize: 16, height: 1.4),
              ),
              const Text(
                'Empty your pile to bury them.',
                style: TextStyle(color: Palette.ink, fontSize: 16, height: 1.4),
              ),
              if (lastWinner != null) ...[
                const SizedBox(height: 18),
                Text('Last bury: $lastWinner', style: const TextStyle(color: Palette.glow, fontSize: 16)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
