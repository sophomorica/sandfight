import 'package:flutter/material.dart';

import '../../game/rules.dart';
import '../../game/throw_ray.dart';
import '../../theme/palette.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.match, required this.seat, required this.onRematch, required this.onLeave});

  final Match match;
  final Seat seat;
  final VoidCallback onRematch;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final title = switch (match.endReason) {
      EndReason.link => 'Link lost',
      EndReason.draw => 'Draw',
      _ => match.winner == seat ? 'Buried' : 'Clear',
    };
    return Scaffold(
      backgroundColor: Palette.pit,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text(title, style: const TextStyle(color: Palette.ink, fontSize: 64, fontWeight: FontWeight.w700, height: 0.95)),
              const SizedBox(height: 12),
              Text(
                'You ${match.massOf(seat)} · Them ${match.massOf(otherSeat(seat))}',
                style: const TextStyle(color: Palette.beige, fontSize: 18),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: FilledButton(
                  key: const ValueKey('rematch'),
                  style: FilledButton.styleFrom(backgroundColor: Palette.beige, foregroundColor: Palette.pit),
                  onPressed: onRematch,
                  child: const Text('Rematch', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const ValueKey('result-leave'),
                onPressed: onLeave,
                child: const Text('Leave', style: TextStyle(color: Palette.dust, fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
